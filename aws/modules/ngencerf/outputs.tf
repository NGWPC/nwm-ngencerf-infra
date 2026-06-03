output "alb_arn" {
  value       = module.alb.arn
  description = "ALB ARN. Consumed by aws_wafv2_web_acl_association in waf.tf."
}

output "alb_dns_name" {
  value       = module.alb.dns_name
  description = "Public DNS name of the ALB. Use to curl the stack: http://<this-value>/"
}

output "compute_ami_id" {
  value       = var.build_compute_ami ? one(aws_imagebuilder_image.pcs_compute[0].output_resources[0].amis[*].image) : null
  description = "AMI ID of the custom PCS compute-node image once built (build_compute_ami = true), else null. Pin into pcs_compute_ami_id so the compute node group uses it."
}
