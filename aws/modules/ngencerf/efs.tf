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
# target in their own AZ, required for the NFS client to connect.
resource "aws_efs_mount_target" "main" {
  count           = length(var.private_subnet_ids)
  file_system_id  = aws_efs_file_system.main.id
  subnet_id       = var.private_subnet_ids[count.index]
  security_groups = [aws_security_group.efs.id]
}

# EFS access points for the Django Fargate task. Each exposes a subtree of the
# one filesystem as its own root and AUTO-CREATES that subtree on first mount
# (creation_info), so a fresh EFS needs no manual mkdir. No posix_user block:
# access is NOT pinned to a fixed uid, so the Django task (root) and the PCS
# compute nodes (root, raw EFS mount) read/write the same files with no uid
# mismatch. Compute nodes mount the EFS ROOT directly (pcs.tf launch template),
# not through these access points.
#   - cal_data:    /data/ngen-cal-data -> Django /ngencerf/data       (CONTAINER_DATA_ROOT)
#   - singularity: /singularity        -> Django /ngencerf/containers  (SINGULARITY_DIR)
# AC-6: each task mount is scoped to its own subtree.

resource "aws_efs_access_point" "cal_data" {
  file_system_id = aws_efs_file_system.main.id

  root_directory {
    path = "/data/ngen-cal-data"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0755"
    }
  }

  tags = {
    Name = "${var.name_prefix}-efs-cal-data"
  }
}

resource "aws_efs_access_point" "singularity" {
  file_system_id = aws_efs_file_system.main.id

  root_directory {
    path = "/singularity"
    creation_info {
      owner_uid   = 0
      owner_gid   = 0
      permissions = "0755"
    }
  }

  tags = {
    Name = "${var.name_prefix}-efs-singularity"
  }
}
