.PHONY: help init plan apply destroy bootstrap smoke fmt lint pre-commit-install _check_env

ENV ?= personal-dev
TERRAFORM_DIR := aws/envs/$(ENV)

help:
	@echo "Targets (pass ENV=<env>, default personal-dev):"
	@echo "  Valid envs: personal-dev, test/dev, test/dev2, test/perf,"
	@echo "              test/integration, optimization/ea, optimization/uat,"
	@echo "              optimization/uat2"
	@echo ""
	@echo "  init                - terraform init (uses env's backend.hcl)"
	@echo "  plan                - terraform plan"
	@echo "  apply               - terraform apply"
	@echo "  destroy             - terraform destroy"
	@echo "  bootstrap           - stage workload SIFs onto EFS (after first apply)"
	@echo "  smoke               - end-to-end smoke test"
	@echo "  fmt                 - terraform fmt -recursive"
	@echo "  lint                - tflint + checkov"
	@echo "  pre-commit-install  - install pre-commit hooks (one-time)"
	@echo ""
	@echo "Usage: make plan ENV=test/dev"
	@echo ""
	@echo "Bootstrap (one-time per AWS account, see aws/bootstrap/README.md):"
	@echo "  cd aws/bootstrap && terraform init && terraform apply"

_check_env:
	@if [ ! -d "$(TERRAFORM_DIR)" ]; then \
		echo "ERROR: env '$(ENV)' not found. Valid: personal-dev, test/{dev,dev2,perf,integration}, optimization/{ea,uat,uat2}"; \
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
