variable "allowed_hosts" {
  type        = list(string)
  description = "Extra hostnames added to Django's ALLOWED_HOSTS beyond the env's own ALB DNS name (django.tf always includes that). Set the public/custom domain here for prod-tier envs (e.g. [\"ngencerf.example.com\"]); empty is fine for personal-dev, reached directly via the ALB DNS."
  default     = []
}

variable "build_compute_ami" {
  type        = bool
  description = "When true, provisions the EC2 Image Builder pipeline (imagebuilder.tf) that bakes the custom PCS compute-node AMI from a clean Ubuntu 24.04 base: AWS PCS agent + Slurm 25.05 + Apptainer + amazon-efs-utils. A build runs a ~20-30 min build instance, so it's a separate opt-in from enable_pcs. After building, read the compute_ami_id output and pin it into pcs_compute_ami_id. Default false so no env builds unless asked."
  default     = false
}

variable "enable_pcs" {
  type        = bool
  description = "When true, provisions the AWS PCS (managed Slurm) cluster, compute (default + heavy) + login node groups, the two named queues, node IAM instance profile, security group, and launch template (all in pcs.tf). Default false so NGWPC envs stay untouched; set true only in personal-dev until the Slurm-direct submission path is proven."
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

variable "pcs_compute_ami_id" {
  type        = string
  description = "AMI ID for the PCS compute node groups. When set (typically the compute_ami_id output from a build_compute_ami run), both compute node groups use this custom AMI; empty falls back to the PCS sample AMI. The login node always uses the sample AMI. Default empty."
  default     = ""
}

variable "pcs_compute_default_instance_type" {
  type        = string
  description = "EC2 instance type for the PCS default compute node group, which backs the c5n-9xlarge queue (jobs with <=500 catchments; up to 6 cpus-per-task on a single node). Prod intent is c5n.9xlarge; personal-dev default c6i.2xlarge (8 vCPU) is the cheapest that satisfies 6 cpus-per-task at min size 0 (no idle cost)."
  default     = "c6i.2xlarge"
}

variable "pcs_compute_heavy_instance_type" {
  type        = string
  description = "EC2 instance type for the PCS heavy compute node group, which backs the r8a-12xlarge queue (jobs with >500 catchments; up to 18 cpus-per-task on a single node). Prod intent is r8a.12xlarge; personal-dev default c6i.8xlarge (32 vCPU) is the cheapest that satisfies 18 cpus-per-task at min size 0 (no idle cost)."
  default     = "c6i.8xlarge"
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

variable "sif_workloads" {
  type        = map(string)
  description = "Workload SIFs to stage onto EFS for AWS PCS jobs: map of workload name -> OCI artifact tag. For each entry the sif-sync bootstrap task (sif_sync.tf) pulls ghcr.io/ngwpc/<name>-sif:<tag> onto EFS /singularity, writes <name>-<tag>.sif, and repoints the stable <name>.sif symlink. Names follow the workload images, e.g. \"nwm-cal-mgr\", \"nwm-fcst-mgr\", \"nwm-verf\". Only used when enable_pcs = true; staged via `make bootstrap`. Default empty (no SIFs staged)."
  default     = {}
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
