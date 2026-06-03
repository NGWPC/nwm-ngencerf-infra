output "alb_dns_name" {
  value       = module.ngencerf.alb_dns_name
  description = "Public DNS name of the ALB. curl http://<this-value>/."
}

output "compute_ami_id" {
  value       = module.ngencerf.compute_ami_id
  description = "Custom PCS compute-node AMI ID once built (build_compute_ami = true). Pin into the module's pcs_compute_ami_id."
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "Private subnet IDs."
}

output "public_subnet_ids" {
  value       = module.vpc.public_subnets
  description = "Public subnet IDs."
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "VPC ID."
}
