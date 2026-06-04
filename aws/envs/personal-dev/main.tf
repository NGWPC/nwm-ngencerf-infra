# envs/personal-dev/main.tf — developer sandbox in a non-LZA AWS account.
#
# Creates the VPC here (no LZA in this account) and passes the IDs into
# module "ngencerf". NGWPC envs (envs/test/*, envs/optimization/*) use data
# sources instead of creating a VPC. Same module, two callers.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  vpc_cidr = "10.42.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "ngencerf-personal-dev-vpc"
  cidr = local.vpc_cidr

  azs = local.azs

  public_subnets  = [for i in range(2) : cidrsubnet(local.vpc_cidr, 4, i)]
  private_subnets = [for i in range(2) : cidrsubnet(local.vpc_cidr, 4, i + 8)]

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags  = { Tier = "public" }
  private_subnet_tags = { Tier = "private" }
}

moved {
  from = module.ngencerf.module.vpc
  to   = module.vpc
}

module "ngencerf" {
  source = "../../modules/ngencerf"

  name_prefix = "ngencerf-personal-dev"

  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets
  public_subnet_ids  = module.vpc.public_subnets

  production = false

  # PCS (managed Slurm) — personal-dev only; NGWPC envs keep the false default.
  enable_pcs = true

  # The compute AMI is pre-baked by imagebuilder.tf and pinned below; keep this
  # false to reuse it (flip true + bump the component/recipe version to rebuild).
  build_compute_ami = false

  # Pin compute to the baked AMI (the compute_ami_id output from the build above).
  pcs_compute_ami_id = "ami-0b19a96fdebfadced"

  ngencerf_server_image = "ghcr.io/ngwpc/ngencerf-server:20260603004352Z-mpena-aws-migration"
  ngencerf_ui_image     = "ghcr.io/ngwpc/ngencerf-ui:20260601051845Z-mpena-aws-migration"

  # Workload SIFs staged onto EFS by `make bootstrap` (sif_sync.tf): name -> OCI tag.
  # Each pulls ghcr.io/ngwpc/<name>-sif:<tag> and repoints the <name>.sif symlink.
  sif_workloads = {
    "nwm-cal-mgr"  = "20260603180913z-mpena-aws-migration"
    "nwm-fcst-mgr" = "20260604040557z-mpena-aws-migration"
    "nwm-verf"     = "20260604040613z-mpena-aws-migration"
  }

  rds_instance_class        = "db.t4g.micro"
  rds_allocated_storage_gib = 20
  redis_node_type           = "cache.t4g.micro"
}
