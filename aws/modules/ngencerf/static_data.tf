# Static-data staging (static-data) — a one-off BOOTSTRAP task that seeds the
# shared EFS with the ngen static-input tree (module parameter files, BMI forcing
# templates, the forcing static dir, NWM retrospective) that ngen reads at
# runtime. A freshly created EFS is empty; this loads the tree ONCE at bring-up.
# Same bootstrap pattern as sif-sync (sif_sync.tf): Terraform creates the task
# here (existence); `make bootstrap` runs it once after `apply` (Twelve-Factor: a
# one-off admin process, kept out of `apply` per HashiCorp's "provisioners are a
# last resort"). `make load-static` re-runs just this task to refresh the tree.
#
# Mechanism: a STANDALONE ECS task (RunTask, runs-to-completion — not a service)
# using the public AWS CLI image to `aws s3 sync` the static tree from the
# Data-account bucket ngwpc-dev onto the EFS cal-data access point under
# ngen-static-files/. That single EFS location is the SAME bytes both tiers read:
# the Django web tier sees it at /ngencerf/data/ngen-static-files and the PCS
# compute nodes see it at /ngencerf-app/data/ngen-cal-data/ngen-static-files.
# ngwpc-dev is the source of truth for the tree; the cross-account read is granted
# to this task role on the Data side (bucket policy / assumable role). All gated
# on enable_pcs so NGWPC envs without PCS are untouched.
# SC-7: dedicated egress-only SG, private subnet. AC-6: task role scoped to the
# one EFS file system and read-only on the two source prefixes.

locals {
  # Runs as `/bin/sh -c <this>` (the aws-cli image entrypoint is overridden
  # below). `aws s3 sync` copies only what is missing, so re-runs are cheap; a
  # fresh EFS pulls the whole tree (tens of GiB, a few minutes). The forcing
  # static dir is a separate source prefix synced into a subdir.
  static_data_command = <<-EOT
    set -eu
    dest=/mnt/data/ngen-static-files
    mkdir -p "$dest"
    echo "Syncing s3://ngwpc-dev/ngen-static-files -> $dest ..."
    aws s3 sync s3://ngwpc-dev/ngen-static-files "$dest" --no-progress
    echo "Syncing s3://ngwpc-dev/rte-test-data/esmf -> $dest/forcing_static_dir ..."
    aws s3 sync s3://ngwpc-dev/rte-test-data/esmf "$dest/forcing_static_dir" --no-progress
    echo "Static data staged. Top level:"
    ls -la "$dest"
  EOT
}

resource "aws_cloudwatch_log_group" "static_data" {
  count             = var.enable_pcs ? 1 : 0
  name              = "/aws/ecs/${var.name_prefix}/static-data"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.main.arn
}

# Dedicated SG: egress to S3 + the public image pull (via NAT / endpoints);
# paired with the EFS ingress rule below to reach the shared filesystem.
# Egress-only, no inbound. SC-7.
resource "aws_security_group" "static_data" {
  count       = var.enable_pcs ? 1 : 0
  name        = "${var.name_prefix}-static-data-sg"
  description = "One-off static-data staging task: egress to S3 + image pull, NFS to EFS."
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "static_data_egress_all" {
  count             = var.enable_pcs ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.static_data[0].id
  description       = "All egress (S3 sync + public image pull via NAT/endpoints)"
}

resource "aws_security_group_rule" "efs_ingress_static_data" {
  count                    = var.enable_pcs ? 1 : 0
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.static_data[0].id
  security_group_id        = aws_security_group.efs.id
  description              = "NFS from the static-data staging task"
}

# Task role: mounts the EFS cal-data access point (mirrors django_efs /
# sif_sync_efs) and reads the source tree from the Data-account bucket.
resource "aws_iam_role" "static_data_task" {
  count              = var.enable_pcs ? 1 : 0
  name               = "${var.name_prefix}-static-data-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# EFS mount. AC-6: scoped to the one EFS file system; no wildcards.
data "aws_iam_policy_document" "static_data_efs" {
  count = var.enable_pcs ? 1 : 0
  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]
    resources = [aws_efs_file_system.main.arn]
  }
}

resource "aws_iam_role_policy" "static_data_efs" {
  count  = var.enable_pcs ? 1 : 0
  name   = "efs-access"
  role   = aws_iam_role.static_data_task[0].name
  policy = data.aws_iam_policy_document.static_data_efs[0].json
}

# Cross-account read on the Data-account source bucket. The Data side must also
# grant this role (bucket policy / assumable role) for the read to succeed.
# AC-6: read-only, scoped to the two source prefixes. If ngwpc-dev is SSE-KMS,
# add kms:Decrypt on its key here too.
data "aws_iam_policy_document" "static_data_s3" {
  count = var.enable_pcs ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::ngwpc-dev"]
  }
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "arn:aws:s3:::ngwpc-dev/ngen-static-files/*",
      "arn:aws:s3:::ngwpc-dev/rte-test-data/esmf/*",
    ]
  }
}

resource "aws_iam_role_policy" "static_data_s3" {
  count  = var.enable_pcs ? 1 : 0
  name   = "s3-read"
  role   = aws_iam_role.static_data_task[0].name
  policy = data.aws_iam_policy_document.static_data_s3[0].json
}

# Standalone task definition (single, not per-workload). No service — run on
# demand by `make bootstrap` / `make load-static` (aws/scripts/bootstrap.sh).
# Reuses the shared ECS execution role (pulls the public image + writes logs; no
# secrets). Mounts only the cal-data access point; writes as root (user 0) to
# ngen-static-files/ under it, matching how the compute nodes write the same EFS.
# The aws-cli image entrypoint is overridden to /bin/sh -c so the sync script
# runs; the task uses its task-role credentials automatically (no profile).
resource "aws_ecs_task_definition" "static_data" {
  count                    = var.enable_pcs ? 1 : 0
  family                   = "${var.name_prefix}-static-data"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "1024"
  memory                   = "2048"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.static_data_task[0].arn

  container_definitions = jsonencode([
    {
      name       = "static-data"
      image      = "public.ecr.aws/aws-cli/aws-cli:2.15.0"
      essential  = true
      user       = "0"
      entryPoint = ["/bin/sh", "-c"]
      command    = [local.static_data_command]

      environment = [
        { name = "HOME", value = "/tmp" },
      ]

      mountPoints = [
        {
          sourceVolume  = "cal-data"
          containerPath = "/mnt/data"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.static_data[0].name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "static-data"
        }
      }
    }
  ])

  volume {
    name = "cal-data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.cal_data.id
        iam             = "DISABLED"
      }
    }
  }
}
