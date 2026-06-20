variable "alb_internal" {
  type        = bool
  description = "When true, the ALB is internal (scheme = internal) and attaches to private_subnet_ids instead of public_subnet_ids; reach it over the VPC / Transit Gateway path, not the internet. Default false keeps the internet-facing ALB on public subnets. Set true for private-only VPCs that have no public subnets (e.g. the LZA SBOX-Compute VPC); pass public_subnet_ids = [] in that case."
  default     = false
}

variable "allowed_hosts" {
  type        = list(string)
  description = "Extra hostnames added to Django's ALLOWED_HOSTS beyond the env's own ALB DNS name (django.tf always includes that). Set the public/custom domain here for prod-tier envs (e.g. [\"ngencerf.example.com\"]); empty is fine for an env reached directly via its ALB DNS."
  default     = []
}

variable "build_compute_ami" {
  type        = bool
  description = "When true, provisions the EC2 Image Builder pipeline (imagebuilder.tf) that bakes the custom PCS compute-node AMI from a clean Ubuntu 24.04 base: AWS PCS agent + Slurm 25.11 + Apptainer + amazon-efs-utils. The compute node groups read that freshly baked AMI directly, so a single apply builds AND uses it (no manual pin). The ~20-30 min bake runs only on the first apply and on image-recipe version bumps, not every apply. Default false so NGWPC envs use the PCS sample AMI (or an explicit pcs_compute_ami_id pin) unless asked to build."
  default     = false
}

variable "enable_pcs" {
  type        = bool
  description = "When true, provisions the AWS PCS (managed Slurm) cluster, compute (default + heavy) + login node groups, the two named queues, node IAM instance profile, security group, and launch template (all in pcs.tf). Default false so envs that do not run compute stay untouched; set true per env that runs PCS (e.g. sandbox)."
  default     = false
}

variable "enterprise_data_env" {
  type        = string
  description = "EDFS / NOAA Enterprise Data Services environment token the server passes to the MSWM hydrofabric client: 'test' or 'oe'. Selects which EDFS host MSWM calls (test -> edfs.test..., oe -> edfs.oe...) and is validated by save_gage_tab. An unset value makes the server raise ValueError(\"Invalid environment: 'None'\"). 'test' for the Test/Sandbox EDFS, 'oe' for Optimization. Keep in sync with enterprise_data_url."
  default     = "test"

  validation {
    condition     = contains(["test", "oe"], var.enterprise_data_env)
    error_message = "enterprise_data_env must be 'test' or 'oe'."
  }
}

variable "enterprise_data_url" {
  type        = string
  description = "Base URL of the EDFS / NOAA Enterprise Data Services endpoint the server fetches hydrofabric geopackages, observational streamflow, and module-parameter metadata from at gage-create time (ENTERPRISE_DATA_URL in settings.py: os.getenv with no in-image default). Test: http://edfs.test.nextgenwaterprediction.com/ ; Optimization: https://edfs.oe.nextgenwaterprediction.com/ . Must match enterprise_data_env. EDFS is private NOAA infra with no public DNS record, so the env's VPC must have a resolver path to it."
  default     = "http://edfs.test.nextgenwaterprediction.com/"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names. Callers should include environment suffix (e.g., \"ngencerf-sandbox\", \"ngencerf-test-dev\") so resource names don't collide when multiple envs share an account."
}

variable "ngencerf_server_image" {
  type        = string
  description = "Full container image URL (including tag) for the Django ECS service. Defaults to public GHCR :latest, which is built from Dockerfile.production-pw and bakes in the RDS CA bundle; runtime config is env-var driven (settings.py reads os.getenv, no local_settings.py). Override per env to pin a specific tag or swap registries (e.g., ECR mirror post-handoff)."
  default     = "ghcr.io/ngwpc/ngencerf-server:latest"
}

variable "ngencerf_ui_image" {
  type        = string
  description = "Full container image URL (including tag) for the Nuxt UI ECS service. Defaults to public GHCR :latest, built from Dockerfile.production-pw in ngencerf-ui. Stateless Nuxt 3 SSR on port 3000; reads NGENCERF_BASE_URL via runtimeConfig at runtime. Override to pin a release tag for prod-tier envs."
  default     = "ghcr.io/ngwpc/ngencerf-ui:latest"
}

variable "pcs_compute_ami_id" {
  type        = string
  description = "Optional explicit AMI-ID pin for the two compute node groups (e.g. a specific external/golden AMI). When non-empty it wins; when empty the node groups use the in-account Image Builder AMI if build_compute_ami = true, else the PCS sample AMI. The login node always uses the sample AMI. Default empty."
  default     = ""
}

variable "pcs_compute_default_instance_type" {
  type        = string
  description = "EC2 instance type for the PCS default compute node group, which backs the c5n-9xlarge queue (jobs with <=500 catchments; up to 6 cpus-per-task on a single node). Prod intent is c5n.9xlarge; the sandbox/dev tier default c6i.2xlarge (8 vCPU) is the cheapest that satisfies 6 cpus-per-task at min size 0 (no idle cost)."
  default     = "c6i.2xlarge"
}

variable "pcs_compute_heavy_instance_type" {
  type        = string
  description = "EC2 instance type for the PCS heavy compute node group, which backs the r8a-12xlarge queue (jobs with >500 catchments; up to 18 cpus-per-task on a single node). Prod intent is r8a.12xlarge; the sandbox/dev tier default c6i.8xlarge (32 vCPU) is the cheapest that satisfies 18 cpus-per-task at min size 0 (no idle cost)."
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

variable "tags" {
  type        = map(string)
  description = "Common tags applied to resources the aws-provider default_tags can't reach: the awscc PCS resources (cluster, compute + login node groups, queues), the PCS launch-template instances + volumes, and the Image Builder output AMI + build instance. Pass the SAME map the env's provider default_tags uses so every resource carries an identical set (incl. the Team tag the Sandbox account enforces via SCP). Default empty so envs relying solely on default_tags (e.g. envs that do not run PCS) are unchanged."
  default     = {}
}

variable "vpc_id" {
  type        = string
  description = "VPC ID. Caller-supplied: env wrappers look up the LZA-laid VPC via data sources and pass the IDs in. The module itself does not create VPCs."
}

variable "waf_rule_action" {
  type        = string
  description = "Action for WAF managed rule groups AND rate-based rules: 'count' (observe only: dev/int) or 'block' (deny matching requests: prod-tier)."
  default     = "count"

  validation {
    condition     = contains(["count", "block"], var.waf_rule_action)
    error_message = "waf_rule_action must be 'count' or 'block'."
  }
}
