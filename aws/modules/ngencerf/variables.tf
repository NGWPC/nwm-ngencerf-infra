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

variable "data_s3_kms_key_arn" {
  type        = string
  description = "KMS CMK ARN in the Data account used to encrypt shared buckets (archive, zips, static data). When set, grants kms:Decrypt, kms:GenerateDataKey, and kms:DescribeKey to the Django task role, and kms:Decrypt and kms:DescribeKey to the PCS node role. Default empty leaves cross-account KMS permissions unmanaged (e.g. if buckets use SSE-S3 or permissions are granted on the key policy)."
  default     = ""
}

variable "db_ingress_cidrs" {
  type        = list(string)
  description = "Extra CIDR blocks allowed to reach RDS Postgres (port 5432) on top of the application web tier. For direct developer/operator database access (e.g. the team's Amazon WorkSpaces) in non-prod envs. Empty by default so prod-tier envs expose the database only to the app."
  default     = []
}

variable "django_cpu" {
  type        = string
  description = "Fargate task-level CPU units for the Django service. Must form a valid Fargate CPU/memory pair with django_memory (e.g. 8192 CPU allows 16384-61440 MiB in 4096 steps). Uniform prod default; override per env."
  default     = "8192"
}

variable "django_memory" {
  type        = string
  description = "Fargate task-level memory (MiB) for the Django service. Must pair validly with django_cpu (8192 CPU -> 16384-61440 MiB). Uniform prod default; override per env."
  default     = "16384"
}

variable "enable_active_directory" {
  type        = bool
  description = "When true, wires Active Directory / LDAP authentication into the Django task: sets ACTIVE_DIRECTORY_ENABLED plus the LDAP_* env vars and injects the bind-account password from ldap_bind_secret_name. Default false leaves standard Django auth (the feature ships in the image but stays off unless an env opts in)."
  default     = false
}

variable "enable_mfa" {
  type        = bool
  description = "When true, turns on mandatory multi-factor authentication in the Django task by setting MFA_ENABLED. The server enforces it after the password check, so it covers every user including Active-Directory-backed ones: on next login each user must enroll an authenticator app (TOTP) and is issued recovery codes. Enrollment state lives in the database, so destroying an env's RDS wipes it and every user re-enrolls on the next bring-up. Default false leaves MFA off (the feature ships in the image but stays off unless an env opts in)."
  default     = false
}

variable "enable_pcs" {
  type        = bool
  description = "When true, provisions the AWS PCS (managed Slurm) cluster, compute (default + heavy) + login node groups, the two named queues, node IAM instance profile, security group, and launch template (all in pcs.tf). Default false so envs that do not run compute stay untouched; set true per env that runs PCS (e.g. sandbox)."
  default     = false
}

variable "enterprise_data_url" {
  type        = string
  description = "Full base API URL of the EDFS / NOAA Enterprise Data Services endpoint the server fetches hydrofabric geopackages, observational streamflow, and module-parameter metadata from (ENTERPRISE_DATA_URL in settings.py: os.getenv with no in-image default). Standard endpoints: 'http://edfs.test.nextgenwaterprediction.com/api/v1/' (Test) or 'https://edfs.oe.nextgenwaterprediction.com/api/v1/' (Optimization); set to the target EDFS API base URL in external deployments (e.g. OWP). EDFS is private NOAA infra with no public DNS record, so the env's VPC must have a resolver path to it."
  default     = "http://edfs.test.nextgenwaterprediction.com/api/v1/"
}

variable "forcing_s3_path" {
  type        = string
  description = "Optional S3 URI prefix (with trailing slash) for observational forcing data (SNODAS / SMAP / SNOTEL), e.g. s3://ngwpc-forcing/. Default empty: ngen-forcing observation reads migrated to static_data_s3_path, so leaving this empty grants no bucket access."
  default     = ""
}

variable "imagebuilder_parent_image" {
  type        = string
  description = "Optional parent image (AMI ID, Image Builder image ARN, or SSM parameter ARN) for the EC2 Image Builder compute-node recipe. When empty, defaults to the Canonical Ubuntu 24.04 LTS SSM parameter (/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id). Default empty."
  default     = ""
}

variable "ldap_bind_dn" {
  type        = string
  description = "LDAP bind identity: the read-only service account the server authenticates AS to look up users, as a userPrincipalName (\"svc-ldap-ro@example.com\") or a full DN. Only used when enable_active_directory = true."
  default     = ""
}

variable "ldap_bind_secret_name" {
  type        = string
  description = "Name of an EXISTING Secrets Manager secret (owned outside this stack) holding the LDAP bind password under a \"password\" key. Looked up by name for its ARN only; the value never enters Terraform state (ECS pulls it at task start). Only used when enable_active_directory = true."
  default     = ""
}

variable "ldap_domain" {
  type        = string
  description = "Active Directory domain name (e.g. \"nextgenwaterprediction.com\"). Passed as LDAP_DOMAIN to the Django task when enable_active_directory = true. Default empty falls back to the container default."
  default     = ""
}

variable "ldap_server_uri" {
  type        = string
  description = "LDAP server URI the Django task binds to, e.g. \"ldap://ad.example.com\" (plain, port 389) or \"ldaps://ad.example.com\" (TLS, port 636). Only used when enable_active_directory = true."
  default     = ""
}

variable "ldap_system_name" {
  type        = string
  description = "Token selecting the AD authorization groups: the server admits members of ngencerf-<name>-users and grants staff to ngencerf-<name>-admins (LDAP_SYSTEM_NAME in settings.py). Only used when enable_active_directory = true."
  default     = ""
}

variable "ldap_user_search_base_dn" {
  type        = string
  description = "Active Directory user search base DN (e.g. \"DC=nextgenwaterprediction,DC=com\"). Passed as LDAP_USER_SEARCH_BASE_DN to the Django task when enable_active_directory = true. Default empty falls back to the container default."
  default     = ""
}

variable "ldap_use_ssl" {
  type        = bool
  description = "When true the LDAP connection uses SSL/TLS (pair with an ldaps:// ldap_server_uri); default false for plain LDAP on port 389. Only used when enable_active_directory = true."
  default     = false
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource names. Callers should include environment suffix (e.g., \"ngencerf-sandbox\", \"ngencerf-test-dev\") so resource names don't collide when multiple envs share an account."
}

variable "ngencerf_archive_s3_path" {
  type        = string
  description = "S3 URI prefix (with trailing slash) where the server writes archived run directories, e.g. s3://ngwpc-ngencerf-archive/<env>/ (NGENCERF_ARCHIVE_S3_PATH, read by cloud_util.py via the Django task role). Each env uses its own unique prefix under the shared Data-account bucket. S3 has no real directories, so seed a .keep object in the prefix before the first archive. Empty leaves it unset."
  default     = ""
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

variable "ngencerf_zips_s3_path" {
  type        = string
  description = "S3 URI prefix (with trailing slash) where the server writes downloadable run zip files, e.g. s3://ngwpc-ngencerf-zips/<env>/ (NGENCERF_ZIPS_S3_PATH, read by cloud_util.py via the Django task role). Each env uses its own unique prefix under the shared Data-account bucket. Seed a .keep object in the prefix before first use. Empty leaves it unset."
  default     = ""
}

variable "nuxt_cpu" {
  type        = string
  description = "Fargate task-level CPU units for the Nuxt UI service. Must form a valid Fargate CPU/memory pair with nuxt_memory (e.g. 2048 CPU allows 4096-16384 MiB in 1024 steps). Uniform prod default; override per env."
  default     = "2048"
}

variable "nuxt_memory" {
  type        = string
  description = "Fargate task-level memory (MiB) for the Nuxt UI service. Must pair validly with nuxt_cpu (2048 CPU -> 4096-16384 MiB). Uniform prod default; override per env."
  default     = "4096"
}

variable "oras_image" {
  type        = string
  description = "Container image URL for the ORAS CLI used by the sif-sync bootstrap task to pull OCI .sif artifacts onto EFS. Override per env for internal registry mirrors (e.g. ECR) in air-gapped or restricted accounts."
  default     = "ghcr.io/oras-project/oras:v1.3.2"
}

variable "pcs_compute_ami_id" {
  type        = string
  description = "Optional explicit AMI-ID pin for the two compute node groups (e.g. a specific external/golden AMI). When non-empty it wins; when empty the node groups use the in-account Image Builder AMI if build_compute_ami = true, else the PCS sample AMI. The login node uses pcs_login_ami_id (or falls back to the sample AMI). Default empty."
  default     = ""
}

variable "pcs_compute_default_instance_type" {
  type        = string
  description = "EC2 instance type for the PCS default compute node group, which backs the c5n-9xlarge queue (jobs with <=500 catchments; up to 6 cpus-per-task on a single node). Uniform prod sizing across all envs: c5n.9xlarge (18 cores). Autoscales from min 0, so idle cost is $0."
  default     = "c5n.9xlarge"
}

variable "pcs_compute_heavy_instance_type" {
  type        = string
  description = "EC2 instance type for the PCS heavy compute node group, which backs the r8a-12xlarge queue (jobs with >500 catchments; up to 18 cpus-per-task on a single node). Uniform prod sizing across all envs: r8a.12xlarge (24 cores). Autoscales from min 0, so idle cost is $0."
  default     = "r8a.12xlarge"
}

variable "pcs_controller_size" {
  type        = string
  description = "AWS PCS controller size: SMALL (up to 32 nodes / 256 jobs), MEDIUM (512 / 8192), or LARGE (2048 / 16384). Sized by node + job count, NOT an EC2 instance type. Default MEDIUM covers the 50-node-per-partition ceiling; override per env."
  default     = "MEDIUM"

  validation {
    condition     = contains(["SMALL", "MEDIUM", "LARGE"], var.pcs_controller_size)
    error_message = "pcs_controller_size must be SMALL, MEDIUM, or LARGE."
  }
}

variable "pcs_login_ami_id" {
  type        = string
  description = "Optional explicit AMI-ID pin for the PCS login node group. When empty, defaults to the AWS PCS DLAMI sample AMI SSM parameter (/aws/service/pcs/ami/dlami-base-ubuntu2404/x86_64/latest/ami-id). Default empty."
  default     = ""
}

variable "pcs_max_nodes_per_partition" {
  type        = number
  description = "Autoscaling ceiling (max_instance_count) for EACH PCS compute node group (default + heavy). min is always 0 so idle cost is $0; this is only the cap. Default 50 (needs a MEDIUM+ controller). Override per env."
  default     = 50
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

variable "public_url" {
  type        = string
  description = "Public HTTPS origin when this env is served through the centralized public edge (e.g. https://ngencerf-ea.nextgenwaterprediction.com). Sets the Django CSRF trusted origin, enables X-Forwarded-Proto trust, and points the UI's browser-facing API base at this origin. Empty (default) leaves all three off for internal-only envs."
  default     = ""
}

variable "rds_allocated_storage_gib" {
  type        = number
  description = "RDS allocated storage in GiB."
  default     = 200
}

variable "rds_instance_class" {
  type        = string
  description = "RDS Postgres instance class."
  default     = "db.r7g.large"
}

variable "redis_node_type" {
  type        = string
  description = "ElastiCache Redis node type."
  default     = "cache.r7g.large"
}

variable "session_manager_logging_policy_arn" {
  type        = string
  description = "Optional explicit IAM policy ARN for Session Manager logging attached to compute and Image Builder instance profiles. When non-empty, overrides session_manager_logging_policy_name. Default empty."
  default     = ""
}

variable "session_manager_logging_policy_name" {
  type        = string
  description = "Name of the account-scoped Session Manager logging policy attached to compute and Image Builder instance profiles. Present in every NGWPC LZA account as AWSAccelerator-SessionManagerLogging. Set to empty string to omit attaching a custom session logging policy (e.g. in non-LZA accounts)."
  default     = "AWSAccelerator-SessionManagerLogging"
}

variable "sif_registry_base" {
  type        = string
  description = "Container registry / repository namespace for workload SIF artifacts. The sif-sync bootstrap task pulls <sif_registry_base>/<name>-sif:<tag>. Override per env to point at an ECR mirror or alternate registry post-handoff."
  default     = "ghcr.io/ngwpc"
}

variable "sif_workloads" {
  type        = map(string)
  description = "Workload SIFs to stage onto EFS for AWS PCS jobs: map of workload name -> OCI artifact tag. For each entry the sif-sync bootstrap task (sif_sync.tf) pulls ghcr.io/ngwpc/<name>-sif:<tag> onto EFS /singularity, writes <name>-<tag>.sif, and repoints the stable <name>.sif symlink. Names follow the workload images, e.g. \"nwm-cal-mgr\", \"nwm-fcst-mgr\", \"nwm-eval-mgr\". Only used when enable_pcs = true; staged via `make bootstrap`. Default empty (no SIFs staged)."
  default     = {}
}

variable "static_data_s3_path" {
  type        = string
  description = "S3 URI prefix (with trailing slash) for static NGen model inputs (retrospective, ESMF), e.g. s3://ngwpc-dev/nwm-tools-data/. Consumed by the PCS node IAM policy and bootstrap static-data staging."
  default     = "s3://ngwpc-dev/nwm-tools-data/"
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
