output "alb_dns_name" {
  value       = module.ngencerf.alb_dns_name
  description = "Public DNS name of the ALB. curl http://<this-value>/."
}

output "compute_ami_id" {
  value       = module.ngencerf.compute_ami_id
  description = "Custom PCS compute-node AMI ID once built (build_compute_ami = true). Pin into the module's pcs_compute_ami_id."
}

output "ecs_cluster_name" {
  value       = module.ngencerf.ecs_cluster_name
  description = "ECS cluster name. Used by bootstrap.sh."
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "Private subnet IDs."
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnets
  description = "Public subnet IDs."
}

output "sif_sync_security_group_id" {
  value       = module.ngencerf.sif_sync_security_group_id
  description = "Security group for the sif-sync bootstrap task. Used by bootstrap.sh."
}

output "sif_sync_task_definitions" {
  value       = module.ngencerf.sif_sync_task_definitions
  description = "Map of workload name -> sif-sync task definition family. bootstrap.sh runs each via `make bootstrap`."
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID."
}
