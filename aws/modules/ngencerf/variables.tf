variable "allowed_hosts" {
  type        = list(string)
  description = "Extra hostnames added to Django's ALLOWED_HOSTS beyond the env's own ALB DNS name (django.tf always includes that). Set the public/custom domain here for prod-tier envs (e.g. [\"ngencerf.example.com\"]); empty is fine for personal-dev, reached directly via the ALB DNS."
  default     = []
}

variable "enable_pcs" {
  type        = bool
  description = "When true, provisions the AWS PCS (managed Slurm) cluster, compute + login node groups, queue, node IAM instance profile, security group, and launch template (all in pcs.tf). Default false so NGWPC envs stay untouched; set true only in personal-dev until the Slurm-direct submission path is proven."
  default     = false
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names. Callers should include environment suffix (e.g., \"ngencerf-personal-dev\", \"ngencerf-test-dev\") so resource names don't collide when multiple envs share an account."
}

variable "ngencerf_server_image" {
  type        = string
  description = "Full container image URL (including tag) for the Django ECS service. Defaults to public GHCR :latest, which is built from Dockerfile.production-pw and bakes in local_settings.py + RDS CA bundle. Override per env to pin a specific tag or swap registries (e.g., ECR mirror post-handoff)."
  default     = "ghcr.io/ngwpc/ngencerf-server:latest"
}

variable "ngencerf_ui_image" {
  type        = string
  description = "Full container image URL (including tag) for the Nuxt UI ECS service. Defaults to public GHCR :latest, built from Dockerfile.production-pw in ngencerf-ui. Stateless Nuxt 3 SSR on port 3000; reads NGENCERF_BASE_URL via runtimeConfig at runtime. Override to pin a release tag for prod-tier envs."
  default     = "ghcr.io/ngwpc/ngencerf-ui:latest"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs (data tier: RDS, EFS, Redis; compute tier: ECS, Lambda)."
}

variable "production" {
  type        = bool
  description = "When true, applies production-safe defaults (multi-AZ RDS, deletion protection, force_destroy off)."
  default     = false
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "Public subnet IDs (ALB)."
}

variable "rds_allocated_storage_gib" {
  type        = number
  description = "RDS allocated storage in GiB."
  default     = 20
}

variable "rds_instance_class" {
  type        = string
  description = "RDS Postgres instance class."
  default     = "db.t4g.micro"
}

variable "redis_node_type" {
  type        = string
  description = "ElastiCache Redis node type."
  default     = "cache.t4g.micro"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID. Caller-supplied: env wrappers either create the VPC (personal-dev) or look it up via data sources (NGWPC envs consuming LZA-laid VPC)."
}

variable "waf_rule_action" {
  type        = string
  description = "Action for WAF managed rule groups AND rate-based rules: 'count' (observe only — dev/int) or 'block' (deny matching requests — prod-tier)."
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_rule_action)
    error_message = "waf_rule_action must be 'count' or 'block'."
  }
}
