# Amazon EFS for shared filesystem across Fargate tasks (Django + job-runner).
# Encrypted with the env-wide CMK; mount target per private-subnet AZ.
# SC-28: at-rest encryption with customer-managed key.
# CP-9: BackupPlan: Daily tag opts into LZA's central backup vault.

resource "aws_efs_file_system" "main" {
  encrypted        = true
  kms_key_id       = aws_kms_key.main.arn
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  # Move cold files to Infrequent Access (10x cheaper); restore on first read
  # so re-access doesn't accumulate per-request charges.
  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name       = "${var.name_prefix}-efs"
    BackupPlan = "Daily"
  }
}

# One mount target per private-subnet AZ. ECS tasks reach EFS via the mount
# target in their own AZ — required for the NFS client to connect.
resource "aws_efs_mount_target" "main" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}
