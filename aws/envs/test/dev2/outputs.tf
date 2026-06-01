output "private_subnet_ids" {
  value       = data.aws_subnets.private.ids
  description = "Private subnet IDs (LZA-laid)."
}

output "public_subnet_ids" {
  value       = data.aws_subnets.public.ids
  description = "Public subnet IDs (LZA-laid)."
}

output "vpc_id" {
  value       = data.aws_vpc.lza.id
  description = "VPC ID (LZA-laid)."
}
