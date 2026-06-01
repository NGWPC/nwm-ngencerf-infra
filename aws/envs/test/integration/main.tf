# envs/test/integration/main.tf — NGWPC Test account, integration env.
# VPC discovered via data sources from LZA-laid VPC. See
# envs/personal-dev/main.tf for the dual-target-VPC pattern.
#
# Fill in the actual VPC/subnet tag patterns below before `terraform plan`.
# Discover them via `aws ec2 describe-vpcs --profile <profile>` against
# this account; the TODO-* placeholders below currently cause plan to fail.

data "aws_vpc" "lza" {
  filter {
    name   = "tag:Name"
    values = ["TODO-vpc-name-pattern"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.lza.id]
  }
  filter {
    name   = "tag:Name"
    values = ["TODO-private-subnet-pattern"]
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.lza.id]
  }
  filter {
    name   = "tag:Name"
    values = ["TODO-public-subnet-pattern"]
  }
}

module "ngencerf" {
  source = "../../../modules/ngencerf"

  name_prefix = "ngencerf-test-integration"

  vpc_id             = data.aws_vpc.lza.id
  private_subnet_ids = data.aws_subnets.private.ids
  public_subnet_ids  = data.aws_subnets.public.ids

  production = true

  rds_instance_class        = "db.r7g.large"
  rds_allocated_storage_gib = 200
  redis_node_type           = "cache.r7g.large"
}
