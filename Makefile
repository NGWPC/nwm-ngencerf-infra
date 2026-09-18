.PHONY: help init plan apply destroy bootstrap load-static smoke fmt lint pre-commit-install _check_env \
	ecs-restart ecs-status slurm-queue slurm-cancel-all slurm-drain slurm-resume login-ssm

ENV ?= sandbox
TERRAFORM_DIR := aws/envs/$(ENV)

help:
	@echo "Targets (pass ENV=<env>, default sandbox):"
	@echo "  Valid envs: sandbox, ea, uat2"
	@echo ""
	@echo "  init                - terraform init (uses env's backend.hcl)"
	@echo "  plan                - terraform plan"
	@echo "  apply               - terraform apply"
	@echo "  destroy             - terraform destroy"
	@echo "  bootstrap           - stage workload SIFs + ngen static data onto EFS (after apply)"
	@echo "  load-static         - re-sync ngen static data onto EFS (static-data stage only)"
	@echo "  ecs-restart         - force new deployment on Django & Nuxt ECS tasks"
	@echo "  ecs-status          - show ECS service status, task counts, and task definitions"
	@echo "  slurm-queue         - show Slurm queue on PCS login node (squeue)"
	@echo "  slurm-cancel-all    - cancel running/pending Slurm jobs (scancel)"
	@echo "  slurm-drain         - drain Slurm partitions before an update (scontrol)"
	@echo "  slurm-resume        - resume Slurm partitions after an update (scontrol)"
	@echo "  login-ssm           - open interactive SSM session to PCS login node"
	@echo "  smoke               - end-to-end smoke test"
	@echo "  fmt                 - terraform fmt -recursive"
	@echo "  lint                - tflint + checkov"
	@echo "  pre-commit-install  - install pre-commit hooks (one-time)"
	@echo ""
	@echo "Usage: make plan ENV=ea"
	@echo ""
	@echo "Bootstrap (one-time per AWS account, see aws/bootstrap/README.md):"
	@echo "  cd aws/bootstrap && terraform init && terraform apply"

_check_env:
	@if [ ! -d "$(TERRAFORM_DIR)" ]; then \
		echo "ERROR: env '$(ENV)' not found. Valid: sandbox, ea, uat2"; \
		exit 1; \
	fi

init: _check_env
	cd $(TERRAFORM_DIR) && terraform init -backend-config=backend.hcl

plan: _check_env
	cd $(TERRAFORM_DIR) && terraform plan

apply: _check_env
	cd $(TERRAFORM_DIR) && terraform apply

bootstrap: _check_env
	bash aws/scripts/bootstrap.sh $(ENV)

load-static: _check_env
	bash aws/scripts/bootstrap.sh $(ENV) static

ecs-restart: _check_env
	bash aws/scripts/ops.sh $(ENV) ecs-restart $(SERVICE)

ecs-status: _check_env
	bash aws/scripts/ops.sh $(ENV) ecs-status

slurm-queue: _check_env
	bash aws/scripts/ops.sh $(ENV) slurm-queue

slurm-cancel-all: _check_env
	bash aws/scripts/ops.sh $(ENV) slurm-cancel-all

slurm-drain: _check_env
	bash aws/scripts/ops.sh $(ENV) slurm-drain

slurm-resume: _check_env
	bash aws/scripts/ops.sh $(ENV) slurm-resume

login-ssm: _check_env
	bash aws/scripts/ops.sh $(ENV) login-ssm

destroy: _check_env
	cd $(TERRAFORM_DIR) && terraform destroy

smoke: _check_env
	bash aws/scripts/smoke.sh $(ENV)

fmt:
	terraform fmt -recursive aws

lint:
	cd aws && tflint --recursive
	checkov -d aws --quiet --compact

pre-commit-install:
	pre-commit install
