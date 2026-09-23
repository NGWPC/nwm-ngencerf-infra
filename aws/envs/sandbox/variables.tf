variable "aws_region" {
  type        = string
  description = "AWS region for this environment."
  default     = "us-east-1"
}

variable "owner" {
  type        = string
  description = "Owner tag value (your name or team identifier)."
}
