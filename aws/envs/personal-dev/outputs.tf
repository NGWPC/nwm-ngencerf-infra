output "alb_dns_name" {
  value       = module.ngencerf.alb_dns_name
  description = "Public DNS name of the ALB. curl http://<this-value>/."
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
