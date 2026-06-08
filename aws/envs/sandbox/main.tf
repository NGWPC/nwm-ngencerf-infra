# envs/sandbox/main.tf — NGWPC Sandbox account, LZA-governed.
# Consumes the existing private-only "SBOX-Compute" VPC via data sources
# (same pattern as envs/test/*). No public subnets, no IGW, no NAT in this
# VPC — egress is via Transit Gateway, and an LZA S3 gateway endpoint already
# exists. The ALB is therefore internal (alb_internal = true) and rides on the
# private subnets; reach it over the TGW path. The custom PCS compute AMI is
# built in-account (build_compute_ami = true) because the personal-dev AMI is
# account-scoped and unusable here. The compute node groups read that freshly
# baked AMI directly, so a single apply builds AND uses it — no manual pin
# (see the enable_pcs block below).

data "aws_vpc" "sbox" {
  filter {
    name   = "tag:Name"
    values = ["SBOX-Compute"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.sbox.id]
  }
  filter {
    name   = "tag:Name"
    values = ["sbox-compute-*"]
  }
}

module "ngencerf" {
  source = "../../modules/ngencerf"

  name_prefix = "ngencerf-sandbox"

  vpc_id             = data.aws_vpc.sbox.id
  private_subnet_ids = data.aws_subnets.private.ids
  public_subnet_ids  = []

  # Private-only VPC: no public subnets exist, so the ALB is internal and
  # binds to the private subnets. Reach it via the VPC / Transit Gateway path.
  alb_internal = true

  production = false

  # PCS (managed Slurm) on, with the compute AMI built in-account: build_compute_ami
  # runs the Image Builder pipeline (~20-30 min on the FIRST apply) and the compute
  # node groups read that freshly baked AMI directly — ONE apply builds and uses it,
  # no manual pin. (The personal-dev AMI is account-scoped, so Sandbox bakes its own.)
  # Leave build_compute_ami = true to keep the custom AMI; it only re-bakes when the
  # image recipe version changes, not on every apply. pcs_compute_ami_id stays empty
  # unless you want to force a specific external AMI.
  enable_pcs         = true
  build_compute_ami  = true
  pcs_compute_ami_id = ""

  # Instance types backing the two Slurm partitions (c5n-9xlarge / r8a-12xlarge).
  # Same cheap picks personal-dev uses; both autoscale from 0 (no idle cost).
  pcs_compute_default_instance_type = "c6i.2xlarge"
  pcs_compute_heavy_instance_type   = "c6i.8xlarge"

  # ngencerf-server and ngencerf-ui Docker images
  ngencerf_server_image = "ghcr.io/ngwpc/ngencerf-server:20260603004352Z-mpena-aws-migration"
  ngencerf_ui_image     = "ghcr.io/ngwpc/ngencerf-ui:20260601051845Z-mpena-aws-migration"

  # Workload SIFs staged onto EFS by `make bootstrap` (sif_sync.tf): name -> OCI tag.
  sif_workloads = {
    "nwm-cal-mgr"  = "20260603180913z-mpena-aws-migration"
    "nwm-fcst-mgr" = "20260604040557z-mpena-aws-migration"
    "nwm-verf"     = "20260604040613z-mpena-aws-migration"
  }

  rds_instance_class        = "db.t4g.micro"
  rds_allocated_storage_gib = 20
  redis_node_type           = "cache.t4g.micro"
}
