# IAM roles for ngencerf services.
#
# All roles, trust policies, and permissions live in this file (HashiCorp
# Style Guide logical-group split). Each role gets:
#   - aws_iam_role with assume_role_policy (who can assume it)
#   - aws_iam_role_policy_attachment for AWS-managed policies (boilerplate)
#   - aws_iam_role_policy for custom least-privilege permissions (inline)

# --- Trust policy documents -------------------------------------------

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "step_functions_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- ECS task execution role ------------------------------------------
# What ECS itself needs: pull image, write logs, fetch secrets.

resource "aws_iam_role" "ecs_task_execution" {
  name               = "${var.name_prefix}-ecs-task-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_managed" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- Django task role -------------------------------------------------
# What the Django app code is allowed to do at runtime. Scoped permissions
# (S3, RDS, CW Logs) attach below.

resource "aws_iam_role" "django_task" {
  name               = "${var.name_prefix}-django-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# --- Step Functions execution role ------------------------------------
# Used by Step Functions state machines.

resource "aws_iam_role" "step_functions" {
  name               = "${var.name_prefix}-step-functions-role"
  assume_role_policy = data.aws_iam_policy_document.step_functions_assume.json
}

# --- Lambda helper role -----------------------------------------------
# Used by helper Lambdas invoked from Step Functions.

resource "aws_iam_role" "lambda_helper" {
  name               = "${var.name_prefix}-lambda-helper-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# --- ECS task execution: fetch secrets at task start ------------------
# AmazonECSTaskExecutionRolePolicy doesn't grant secretsmanager:GetSecretValue
# or kms:Decrypt for customer-managed CMKs. Add explicitly, scoped to the app
# secrets (DB + Django key on our CMK, plus the external LDAP bind secret when
# AD is enabled) and the secrets CMK. The LDAP secret uses the AWS-managed
# aws/secretsmanager key, which authorizes decrypt via GetSecretValue, so it
# needs no CMK grant. The for expression adds its ARN only when AD is enabled.

data "aws_iam_policy_document" "ecs_task_execution_secrets" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = concat([
      aws_secretsmanager_secret.db.arn,
      aws_secretsmanager_secret.django_secret_key.arn,
    ], [for s in data.aws_secretsmanager_secret.ldap_bind : s.arn])
  }
  statement {
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.main.arn]
  }
}

resource "aws_iam_role_policy" "ecs_task_execution_secrets" {
  name   = "secrets-access"
  role   = aws_iam_role.ecs_task_execution.name
  policy = data.aws_iam_policy_document.ecs_task_execution_secrets.json
}

locals {
  # Parse S3 URI prefix strings (e.g. s3://bucket/path/) into bucket and prefix.
  # Handles empty strings, optional trailing slashes, and prefix extraction.
  s3_inputs = {
    archive = var.ngencerf_archive_s3_path
    zips    = var.ngencerf_zips_s3_path
    forcing = var.forcing_s3_path
    static  = var.static_data_s3_path
  }

  s3_parsed = {
    for k, v in local.s3_inputs : k => (
      can(regex("^s3://([^/]+)", v)) ? {
        bucket = regex("^s3://(?P<bucket>[^/]+)/?(?P<prefix>.*)$", v).bucket
        prefix = regex("^s3://(?P<bucket>[^/]+)/?(?P<prefix>.*)$", v).prefix != "" ? (
          endswith(regex("^s3://(?P<bucket>[^/]+)/?(?P<prefix>.*)$", v).prefix, "/") ?
          regex("^s3://(?P<bucket>[^/]+)/?(?P<prefix>.*)$", v).prefix :
          "${regex("^s3://(?P<bucket>[^/]+)/?(?P<prefix>.*)$", v).prefix}/"
        ) : ""
      } : null
    )
  }

  # Read-write bucket and object ARNs (archive + zips)
  django_rw_bucket_arns = distinct(compact([
    local.s3_parsed.archive != null ? "arn:aws:s3:::${local.s3_parsed.archive.bucket}" : "",
    local.s3_parsed.zips != null ? "arn:aws:s3:::${local.s3_parsed.zips.bucket}" : "",
  ]))

  django_rw_object_arns = distinct(compact([
    local.s3_parsed.archive != null ? "arn:aws:s3:::${local.s3_parsed.archive.bucket}/${local.s3_parsed.archive.prefix}*" : "",
    local.s3_parsed.zips != null ? "arn:aws:s3:::${local.s3_parsed.zips.bucket}/${local.s3_parsed.zips.prefix}*" : "",
  ]))

  # Read-only bucket and object ARNs (static data, and legacy forcing if configured)
  django_ro_bucket_arns = distinct(compact([
    local.s3_parsed.static != null ? "arn:aws:s3:::${local.s3_parsed.static.bucket}" : "",
    local.s3_parsed.forcing != null ? "arn:aws:s3:::${local.s3_parsed.forcing.bucket}" : "",
  ]))

  django_ro_object_arns = distinct(compact([
    local.s3_parsed.static != null ? "arn:aws:s3:::${local.s3_parsed.static.bucket}/${local.s3_parsed.static.prefix}*" : "",
    local.s3_parsed.forcing != null ? "arn:aws:s3:::${local.s3_parsed.forcing.bucket}/${local.s3_parsed.forcing.prefix}*" : "",
  ]))
}

# --- Django task: scoped S3 access on existing NGWPC buckets ----------
# AC-6: scoped to specific bucket ARNs and environment prefixes, no s3:* wildcards.
# Buckets for archive, zips, and static data are external/shared resources (often
# living in the Data account, owned outside this stack). The cross-account
# access pattern is set on the bucket side; this policy grants the IAM half
# on the consumer side.
#
# When buckets are encrypted by a CMK in the Data account, cross-account
# kms:Decrypt + kms:GenerateDataKey targets var.data_s3_kms_key_arn.

data "aws_iam_policy_document" "django_s3" {
  dynamic "statement" {
    for_each = length(local.django_rw_bucket_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = local.django_rw_bucket_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.django_rw_object_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
      ]
      resources = local.django_rw_object_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.django_ro_bucket_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = local.django_ro_bucket_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.django_ro_object_arns) > 0 ? [1] : []
    content {
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = local.django_ro_object_arns
    }
  }

  dynamic "statement" {
    for_each = var.data_s3_kms_key_arn != "" ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = [var.data_s3_kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "django_s3" {
  name   = "s3-access"
  role   = aws_iam_role.django_task.name
  policy = data.aws_iam_policy_document.django_s3.json
}

# --- Django task: EFS mount permissions -------------------------------
# Fargate tasks mounting EFS need elasticfilesystem:ClientMount + ClientWrite
# granted via IAM on the task role (in addition to SG ingress to EFS:2049).
# Scoped to the env-specific EFS file system ARN.
# AC-6: scoped to a specific EFS file system; no wildcards.

data "aws_iam_policy_document" "django_efs" {
  statement {
    effect = "Allow"
    actions = [
      "elasticfilesystem:ClientMount",
      "elasticfilesystem:ClientWrite",
    ]
    resources = [aws_efs_file_system.main.arn]
  }
}

resource "aws_iam_role_policy" "django_efs" {
  name   = "efs-access"
  role   = aws_iam_role.django_task.name
  policy = data.aws_iam_policy_document.django_efs.json
}

# --- Django task: ECS Exec (ssmmessages) ------------------------------
# Required for `aws ecs execute-command` (interactive shell into a running
# task for ops debugging). ssmmessages doesn't support resource-level
# scoping per AWS IAM docs, so Resource: "*" is correct.
# AC-6: only the django_task role gets exec; AU-2: ECS CloudTrails the
# ExecuteCommand API call.

data "aws_iam_policy_document" "django_exec" {
  statement {
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "django_exec" {
  name   = "exec-command"
  role   = aws_iam_role.django_task.name
  policy = data.aws_iam_policy_document.django_exec.json
}

# --- Nuxt task role ---------------------------------------------------
# UI container is pure HTTP: renders pages, proxies API calls to Django
# via the ALB. No AWS SDK usage, no S3, no Secrets Manager, no DB. Empty
# role for correctness (ECS requires a task role on every task def).
# AC-6: minimal surface; future AWS integrations would scope here.

resource "aws_iam_role" "nuxt_task" {
  name               = "${var.name_prefix}-nuxt-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# --- Nuxt task: ECS Exec (reuses django_exec policy doc) --------------
# Same four ssmmessages channel actions. Reuses the django_exec data doc
# above since the ssmmessages permission shape is identical across tasks.
# AC-6: only nuxt_task gets exec capability for the UI tier.

resource "aws_iam_role_policy" "nuxt_exec" {
  name   = "exec-command"
  role   = aws_iam_role.nuxt_task.name
  policy = data.aws_iam_policy_document.django_exec.json
}
