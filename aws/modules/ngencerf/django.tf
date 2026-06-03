# Django Fargate task + service. Image ghcr.io/ngwpc/ngencerf-server:latest is
# built from Dockerfile.production-pw — RDS CA bundle is baked into the image;
# all config is env-var-driven (no local_settings.py — settings.py reads
# everything via os.getenv). We only inject env vars + secrets here. EFS
# mounted at /ngencerf/data per the CONTAINER_DATA_ROOT constant in
# cerfServer/settings.py:300. assign_public_ip = false; egress via NAT.
# SC-7: data tier reachable only via web SG. AC-6: per-task IAM roles.

locals {
  # slurmrestd (Slurm REST API) endpoint the Django task POSTs jobs to.
  # PCS exposes one endpoint per Slurm daemon; select the SLURMRESTD one.
  pcs_slurmrestd_endpoint = var.enable_pcs ? one([
    for endpoint in awscc_pcs_cluster.main[0].endpoints : endpoint
    if endpoint.type == "SLURMRESTD"
  ]) : null
}

resource "aws_ecs_task_definition" "django" {
  family                   = "${var.name_prefix}-django"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "2048"

  execution_role_arn = aws_iam_role.ecs_task_execution.arn
  task_role_arn      = aws_iam_role.django_task.arn

  container_definitions = jsonencode([
    {
      name      = "django"
      image     = var.ngencerf_server_image
      essential = true

      portMappings = [
        {
          containerPort = 8000
          protocol      = "tcp"
        }
      ]

      environment = concat([
        { name = "DJANGO_DEBUG", value = "False" },
        { name = "ALLOWED_HOSTS", value = join(",", concat([module.alb.dns_name], var.allowed_hosts)) },
        { name = "JOB_EXECUTION_MODE", value = var.enable_pcs ? "SLURM" : "DOCKER" },
        { name = "GUNICORN_WORKERS", value = "2" },
        { name = "PROD_FLAG", value = "1" },
        { name = "CERF_SERVER_DATABASE_NAME", value = "ngencerf" },
        { name = "CERF_SERVER_DATABASE_USER", value = "ngencerf" },
        { name = "CERF_SERVER_DATABASE_HOST", value = module.rds.db_instance_address },
        { name = "REDIS_URL", value = "rediss://${aws_elasticache_replication_group.main.primary_endpoint_address}:6379/1" },
        ], var.enable_pcs ? [
        # Slurm REST API: Django POSTs jobs to slurmrestd on the PCS
        # controller. JOB_EXECUTION_MODE flips to SLURM with the REST-adapter
        # image. NGENCERF_BASE_URL is the base for the callbacks the compute
        # job makes back to Django. get_callback_url()
        # (calibration/run_util/job_executor_slurm.py) builds NGENCERF_BASE_URL +
        # a callback path whose literals are BARE (no /api), as of the server's
        # "Update base endpoints" change, so the /api must live here in the base
        # or the callback 404s against the /api-prefixed routes. Keep the
        # explicit :80 (normalize_base_url appends :8000 otherwise). The Nuxt UI
        # base in nuxt.tf carries /api the same way.
        { name = "NGENCERF_BASE_URL", value = "http://${module.alb.dns_name}:80/api" },
        { name = "SLURM_REST_ENDPOINT", value = "http://${local.pcs_slurmrestd_endpoint.private_ip_address}:${local.pcs_slurmrestd_endpoint.port}" },
        { name = "SLURM_JWT_SECRET_ARN", value = awscc_pcs_cluster.main[0].slurm_configuration.auth_key.secret_arn },
        { name = "SLURM_API_VERSION", value = "v0.0.43" },
        { name = "SLURM_REST_USER", value = "root" },
        { name = "SLURM_REST_UID", value = "0" },
        { name = "SLURM_REST_GID", value = "0" },
        { name = "SLURM_REST_JOB_ENVIRONMENT", value = jsonencode(["PATH=/opt/aws/pcs/scheduler/slurm-25.05/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", "HOME=/root"]) },

        # Host (compute-node) paths the Slurm adapter translates container paths
        # into. The cal-mgr job runs on a compute node where the EFS root is
        # mounted at /ngencerf-app (pcs.tf launch template). HOST_DATA_ROOT is the
        # translation target (job_executor_slurm.py:
        # input_file.replace(CONTAINER_DATA_ROOT, HOST_DATA_ROOT)) and the host
        # side of the singularity bind-mount; the SIF path points at the stable
        # symlink so SIF swaps never touch Django. Both are os.getenv with no
        # default in settings.py, so leaving them unset would break a real run.
        { name = "HOST_DATA_ROOT", value = "/ngencerf-app/data/ngen-cal-data" },
        { name = "NWM_CAL_MGR_SINGULARITY_CONTAINER_PATH", value = "/ngencerf-app/singularity/nwm-cal-mgr.sif" },
      ] : [])

      secrets = [
        { name = "CERF_SERVER_DATABASE_PASSWORD", valueFrom = aws_secretsmanager_secret.db.arn },
        { name = "CERF_SERVER_SECRET_KEY", valueFrom = aws_secretsmanager_secret.django_secret_key.arn },
      ]

      mountPoints = [
        {
          sourceVolume  = "data"
          containerPath = "/ngencerf/data"
          readOnly      = false
        },
        {
          sourceVolume  = "containers"
          containerPath = "/ngencerf/containers"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.django.name
          awslogs-region        = data.aws_region.current.name
          awslogs-stream-prefix = "django"
        }
      }
    }
  ])

  # Two EFS volumes via access points (efs.tf). The access point's root_directory
  # makes Django see an EFS subtree as /ngencerf/data + /ngencerf/containers
  # (PW-parity layout). transit_encryption is required with an access point;
  # iam = DISABLED because the access point + EFS SG + the django_efs ClientMount
  # policy already gate access (no per-access-point IAM enforcement).
  volume {
    name = "data"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.cal_data.id
        iam             = "DISABLED"
      }
    }
  }

  volume {
    name = "containers"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.main.id
      transit_encryption = "ENABLED"
      authorization_config {
        access_point_id = aws_efs_access_point.singularity.id
        iam             = "DISABLED"
      }
    }
  }
}

resource "aws_ecs_service" "django" {
  name                   = "${var.name_prefix}-django"
  cluster                = aws_ecs_cluster.main.id
  task_definition        = aws_ecs_task_definition.django.arn
  desired_count          = 1
  launch_type            = "FARGATE"
  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.web.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = module.alb.target_groups["django"].arn
    container_name   = "django"
    container_port   = 8000
  }

  health_check_grace_period_seconds  = 600
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  depends_on = [aws_efs_mount_target.main]
}
