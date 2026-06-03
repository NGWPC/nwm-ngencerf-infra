# AWS PCS (Parallel Computing Service) — managed Slurm.
#
# PCS resources live in the `awscc` (AWS Cloud Control) provider, NOT the
# classic `aws` provider — `aws` has no PCS resources. `awscc` is AWS's
# auto-generated provider over the Cloud Control API; AWS officially blesses
# it for PCS Terraform. The two providers run side by side: the cluster,
# compute node groups, and queue come from `awscc`; the supporting IAM,
# security group, launch template, and AMI lookup stay in `aws`.
#
# Everything here is gated behind var.enable_pcs (default false). Only
# personal-dev sets it true today; NGWPC envs are untouched until the
# Slurm-direct submission path is proven.
#
# Submission model = Slurm REST API: Django (on Fargate) POSTs jobs
# to slurmrestd on the controller (port 6820, JWT). The login node group below
# is kept as a testing/ops on-ramp — SSM in to drive Slurm by hand (verify
# scheduling, debug). It is NOT in the submission path; Django uses the REST
# API above.

# --- PCS node AMI -------------------------------------------------------
# AWS publishes PCS-ready sample AMIs as SSM public parameters. Verified in
# this account: only the Ubuntu 24.04 DLAMI-base flavor is published. The AMI
# bakes the PCS/Slurm agent, so a minimal cluster needs no user_data.

data "aws_ssm_parameter" "pcs_ami" {
  count = var.enable_pcs ? 1 : 0
  name  = "/aws/service/pcs/ami/dlami-base-ubuntu2404/x86_64/latest/ami-id"
}

# --- PCS node IAM -------------------------------------------------------
# Compute + login instances register with the cluster and are managed over
# SSM (no SSH). The role NAME must start with "AWSPCS" (or use path
# /aws-pcs/) — PCS requires this prefix to recognize the instance profile.
# AC-6: pcs:RegisterComputeNodeGroupInstance is the only inline grant; SSM +
# CloudWatch come from AWS-managed policies.

data "aws_iam_policy_document" "pcs_node_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "pcs_register" {
  statement {
    effect    = "Allow"
    actions   = ["pcs:RegisterComputeNodeGroupInstance"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "pcs_node" {
  count              = var.enable_pcs ? 1 : 0
  name               = "AWSPCS-${var.name_prefix}-node"
  assume_role_policy = data.aws_iam_policy_document.pcs_node_assume.json
}

resource "aws_iam_role_policy" "pcs_register" {
  count  = var.enable_pcs ? 1 : 0
  name   = "pcs-register-node"
  role   = aws_iam_role.pcs_node[0].id
  policy = data.aws_iam_policy_document.pcs_register.json
}

resource "aws_iam_role_policy_attachment" "pcs_node_ssm" {
  count      = var.enable_pcs ? 1 : 0
  role       = aws_iam_role.pcs_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "pcs_node_cloudwatch" {
  count      = var.enable_pcs ? 1 : 0
  role       = aws_iam_role.pcs_node[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "pcs_node" {
  count = var.enable_pcs ? 1 : 0
  name  = "AWSPCS-${var.name_prefix}-node"
  role  = aws_iam_role.pcs_node[0].name
}

# --- PCS security group -------------------------------------------------
# One SG for the cluster, compute, and login nodes. All-internal: members
# talk to each other on any port (Slurm control + MPI), egress open for SSM,
# package installs, and (later) Django REST callbacks. The slurmrestd:6820
# ingress from the web tier is added with the Slurm REST API wiring, not here.
# SC-7: no inbound from the internet.

resource "aws_security_group" "pcs" {
  count       = var.enable_pcs ? 1 : 0
  name        = "${var.name_prefix}-pcs-sg"
  description = "AWS PCS cluster, compute, and login nodes (all-internal)."
  vpc_id      = var.vpc_id
}

resource "aws_security_group_rule" "pcs_ingress_self" {
  count             = var.enable_pcs ? 1 : 0
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.pcs[0].id
  description       = "All traffic between PCS nodes (Slurm control + MPI)"
}

resource "aws_security_group_rule" "pcs_egress_all" {
  count             = var.enable_pcs ? 1 : 0
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.pcs[0].id
  description       = "All egress (SSM, package installs, callbacks)"
}

# --- EFS reachability from PCS nodes ------------------------------------
# Opens 2049 (NFS) on the EFS SG to the PCS SG so compute + login nodes can
# mount the shared filesystem the launch template configures below. The EFS SG
# otherwise admits only the web tier (efs_ingress_web in security_groups.tf).
# Gated on enable_pcs because the PCS SG only exists then, and kept here (not in
# security_groups.tf) so tearing out PCS removes this with it — same pattern as
# pcs_ingress_web_slurmrestd.

resource "aws_security_group_rule" "efs_ingress_pcs" {
  count                    = var.enable_pcs ? 1 : 0
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.pcs[0].id
  security_group_id        = aws_security_group.efs.id
  description              = "NFS from PCS compute + login nodes"
}

# --- PCS node launch template -------------------------------------------
# Shared by the compute and login node groups. Carries the PCS SG, enforces
# IMDSv2, and mounts the shared EFS. Instance type is set per node group
# (instance_configs), not here. IMDSv2-only hardens the instance metadata
# endpoint against SSRF credential theft.

resource "aws_launch_template" "pcs" {
  count       = var.enable_pcs ? 1 : 0
  name        = "${var.name_prefix}-pcs-node"
  description = "PCS compute + login node settings: PCS SG, IMDSv2, EFS mount."

  vpc_security_group_ids = [aws_security_group.pcs[0].id]

  # Mount the shared EFS at /ngencerf/data via cloud-init.
  #
  # PCS REQUIRES launch-template user_data to be a MIME multipart archive: it
  # merges its own node-bootstrap (Slurm agent registration) into your parts.
  # Plain shell-script user_data would replace that bootstrap and the node would
  # never join the cluster. The text/cloud-config part runs before the node
  # registers with the PCS API.
  #
  # amazon-efs-utils provides the `efs` mount type with `tls` (in-transit
  # encryption) — matching the Django mount (transit_encryption = ENABLED in
  # django.tf). The path /ngencerf/data matches Django's containerPath and
  # settings.py CONTAINER_DATA_ROOT, so compute nodes and Django share ONE
  # filesystem — the Slurm adapter assumes a single shared FS. Mounting by
  # file-system-id (not DNS) lets the efs helper pick the AZ-local mount target.
  # SC-28: encryption in transit.
  user_data = base64encode(<<EOT
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/cloud-config; charset="us-ascii"

packages:
  - amazon-efs-utils

runcmd:
  - mkdir -p /ngencerf/data
  - echo "${aws_efs_file_system.main.id}:/ /ngencerf/data efs tls,_netdev" >> /etc/fstab
  - mount -a -t efs defaults

--==MYBOUNDARY==--
EOT
  )

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name_prefix}-pcs-node"
    }
  }
}

# --- PCS cluster (awscc) ------------------------------------------------
# SMALL controller, Slurm 25.05 (minimum version that supports BOTH accounting
# and the Slurm REST API). accounting=STANDARD records job history (sacct) and
# is a prerequisite for slurmrestd. slurm_rest=STANDARD turns on slurmrestd
# (port 6820, JWT) — the Django submission door. Idle compute scales down after
# 5 minutes.
#
# COST: the SMALL controller bills hourly even at 0 compute, and accounting
# adds a second hourly fee — NOT free. Destroy at end of day.

resource "awscc_pcs_cluster" "main" {
  count = var.enable_pcs ? 1 : 0
  name  = "${var.name_prefix}-pcs"
  size  = "SMALL"

  scheduler = {
    type    = "SLURM"
    version = "25.05"
  }

  networking = {
    subnet_ids         = [var.private_subnet_ids[0]]
    security_group_ids = [aws_security_group.pcs[0].id]
  }

  slurm_configuration = {
    accounting = {
      mode                       = "STANDARD"
      default_purge_time_in_days = 7
    }
    scale_down_idle_time_in_seconds = 300
    slurm_rest = {
      mode = "STANDARD"
    }
  }

  tags = {
    Name = "${var.name_prefix}-pcs"
  }
}

# --- Compute node group (awscc) -----------------------------------------
# Autoscales 0 -> 4 on demand; runs the calibration/forecast/verification
# jobs. min=0 means $0 of compute when idle — only the controller bills.

resource "awscc_pcs_compute_node_group" "compute" {
  count      = var.enable_pcs ? 1 : 0
  name       = "compute"
  cluster_id = awscc_pcs_cluster.main[0].cluster_id
  ami_id     = var.pcs_compute_ami_id != "" ? var.pcs_compute_ami_id : nonsensitive(data.aws_ssm_parameter.pcs_ami[0].value)

  custom_launch_template = {
    template_id = aws_launch_template.pcs[0].id
    version     = tostring(aws_launch_template.pcs[0].latest_version)
  }

  iam_instance_profile_arn = aws_iam_instance_profile.pcs_node[0].arn

  instance_configs = [{
    instance_type = "c6i.xlarge"
  }]

  scaling_configuration = {
    min_instance_count = 0
    max_instance_count = 4
  }

  subnet_ids = var.private_subnet_ids
}

# --- Login node group (awscc) -------------------------------------------
# A single always-on node we SSM into to drive Slurm by hand
# (`sbatch`/`squeue`/`sacct`/`sinfo`). It is NOT attached to the queue, so the
# scheduler never places jobs on it, and it is NOT in the job-submission path:
# Django submits straight to the Slurm REST API (slurmrestd), never through this
# node. KEPT purely as a TESTING + ops on-ramp — a place to SSM in and inspect
# or drive Slurm directly (verify scheduling, debug job state, run a manual
# job). Nothing in the application depends on it; safe to remove if a standing
# ops box isn't wanted.

resource "awscc_pcs_compute_node_group" "login" {
  count      = var.enable_pcs ? 1 : 0
  name       = "login"
  cluster_id = awscc_pcs_cluster.main[0].cluster_id
  ami_id     = nonsensitive(data.aws_ssm_parameter.pcs_ami[0].value)

  custom_launch_template = {
    template_id = aws_launch_template.pcs[0].id
    version     = tostring(aws_launch_template.pcs[0].latest_version)
  }

  iam_instance_profile_arn = aws_iam_instance_profile.pcs_node[0].arn

  instance_configs = [{
    instance_type = "c6i.large"
  }]

  scaling_configuration = {
    min_instance_count = 1
    max_instance_count = 1
  }

  subnet_ids = [var.private_subnet_ids[0]]
}

# --- Queue (awscc) ------------------------------------------------------
# Maps to a Slurm partition. Jobs submitted to the "normal" queue land on the
# compute node group (not login).

resource "awscc_pcs_queue" "normal" {
  count      = var.enable_pcs ? 1 : 0
  name       = "normal"
  cluster_id = awscc_pcs_cluster.main[0].cluster_id

  compute_node_group_configurations = [{
    compute_node_group_id = awscc_pcs_compute_node_group.compute[0].compute_node_group_id
  }]
}

# --- Slurm REST API wiring: Django (web tier) -> slurmrestd -------------
# Lets the Django Fargate task submit jobs to the cluster over the Slurm REST
# API (slurmrestd, port 6820). Part of the PCS feature, so gated on
# var.enable_pcs and kept here — removing PCS removes this too.

# slurmrestd:6820 ingress from the Django web SG. The web SG already has
# all-egress, so this inbound rule is the only opening needed.
# SC-7: still no path from the internet; only the web tier reaches the API.
resource "aws_security_group_rule" "pcs_ingress_web_slurmrestd" {
  count                    = var.enable_pcs ? 1 : 0
  type                     = "ingress"
  from_port                = 6820
  to_port                  = 6820
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.web.id
  security_group_id        = aws_security_group.pcs[0].id
  description              = "slurmrestd (Slurm REST API) from the Django web tier"
}

# Django signs a JWT with the cluster's JWT key to call slurmrestd. PCS keeps
# that key in a Secrets Manager secret it manages; grant the Django task role
# read access to exactly that secret.
# AC-6: scoped to the single PCS-managed auth-key secret ARN, no wildcards.
data "aws_iam_policy_document" "django_pcs_jwt_secret" {
  count = var.enable_pcs ? 1 : 0
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [awscc_pcs_cluster.main[0].slurm_configuration.auth_key.secret_arn]
  }
}

resource "aws_iam_role_policy" "django_pcs_jwt_secret" {
  count  = var.enable_pcs ? 1 : 0
  name   = "pcs-slurm-jwt-secret"
  role   = aws_iam_role.django_task.name
  policy = data.aws_iam_policy_document.django_pcs_jwt_secret[0].json
}
