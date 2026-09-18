output "alb_dns_name" {
  value       = module.ngencerf.alb_dns_name
  description = "Internal DNS name of the ALB. Reachable over the VPC / Transit Gateway path, not the internet."
}

output "aws_region" {
  value       = module.ngencerf.aws_region
  description = "AWS region where this environment is deployed."
}

output "compute_ami_id" {
  value       = module.ngencerf.compute_ami_id
  description = "Custom PCS compute-node AMI ID once built (build_compute_ami = true). Informational, because the compute node groups already consume this AMI directly in the same apply; no manual pin needed."
}

output "ecs_cluster_name" {
  value       = module.ngencerf.ecs_cluster_name
  description = "ECS cluster name. Used by bootstrap.sh."
}

output "login_ami_id" {
  value       = module.ngencerf.login_ami_id
  description = "PCS login-node AMI ID once provisioned (enable_pcs = true). Informational."
}

output "private_subnet_ids" {
  value       = data.aws_subnets.private.ids
  description = "Private subnet IDs (LZA-laid Test-ngen-Compute VPC)."
}

output "sif_sync_security_group_id" {
  value       = module.ngencerf.sif_sync_security_group_id
  description = "Security group for the sif-sync bootstrap task. Used by bootstrap.sh."
}

output "sif_sync_task_definitions" {
  value       = module.ngencerf.sif_sync_task_definitions
  description = "Map of workload name -> sif-sync task definition family. bootstrap.sh runs each via `make bootstrap`."
}

output "static_data_s3_path" {
  value       = module.ngencerf.static_data_s3_path
  description = "S3 URI prefix where static NGen model inputs are stored. Consumed by bootstrap.sh."
}

output "vpc_id" {
  value       = data.aws_vpc.ngen.id
  description = "VPC ID (LZA-laid Test-ngen-Compute VPC)."
}
