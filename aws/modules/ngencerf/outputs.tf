output "alb_arn" {
  value       = module.alb.arn
  description = "ALB ARN. Consumed by aws_wafv2_web_acl_association in waf.tf."
}

output "alb_dns_name" {
  value       = module.alb.dns_name
  description = "Public DNS name of the ALB. Use to curl the stack: http://<this-value>/"
}
