#!/usr/bin/env bash
#
# bootstrap.sh — one-time-per-bring-up SIF staging.
#
# Runs the standalone sif-sync ECS tasks (modules/ngencerf/sif_sync.tf), one per
# workload in var.sif_workloads, each oras-pulling its pinned SIF onto EFS
# /singularity and repointing the <name>.sif symlink. Run it once after the
# first `terraform apply` for an env, and again after any cold bring-up (a fresh
# EFS is empty). Idempotent; each workload is staged independently.
#
# Usage: make bootstrap ENV=<env>     (or: bash aws/scripts/bootstrap.sh <env>)
#
# Requires: AWS credentials for the target account on the environment (e.g.
# AWS_PROFILE set), the env already `terraform apply`-ed, and jq.

set -euo pipefail

ENV="${1:?usage: bootstrap.sh <env>  (e.g. personal-dev)}"
REGION="us-east-1"
DIR="aws/envs/${ENV}"
PREFIX="ngencerf-$(echo "${ENV}" | tr '/' '-')"

if [ ! -d "${DIR}" ]; then
  echo "ERROR: env dir '${DIR}' not found (run from the repo root)." >&2
  exit 1
fi
cd "${DIR}"

cluster=$(terraform output -raw ecs_cluster_name 2>/dev/null || true)
taskdefs=$(terraform output -json sif_sync_task_definitions 2>/dev/null || echo '{}')
sg=$(terraform output -raw sif_sync_security_group_id 2>/dev/null || true)
subnets=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r 'join(",")' || true)
names=$(echo "${taskdefs}" | jq -r 'keys[]' 2>/dev/null || true)

if [ -z "${cluster}" ] || [ -z "${sg}" ] || [ "${sg}" = "null" ] \
  || [ -z "${subnets}" ] || [ -z "${names}" ]; then
  echo "ERROR: sif-sync outputs missing for env '${ENV}'. Is enable_pcs = true, sif_workloads set, and the env applied?" >&2
  exit 1
fi

netcfg="awsvpcConfiguration={subnets=[${subnets}],securityGroups=[${sg}],assignPublicIp=DISABLED}"
overall=0

# Stage each workload's SIF with its own run-to-completion task. Sequential so a
# failure is clearly attributable; each is attempted regardless of the others.
for name in ${names}; do
  taskdef=$(echo "${taskdefs}" | jq -r --arg n "${name}" '.[$n]')
  echo "=== Staging ${name} (task '${taskdef}') on cluster '${cluster}' (env=${ENV}, region=${REGION})..."

  if ! task_arn=$(aws ecs run-task \
    --cluster "${cluster}" \
    --task-definition "${taskdef}" \
    --launch-type FARGATE \
    --region "${REGION}" \
    --network-configuration "${netcfg}" \
    --query 'tasks[0].taskArn' --output text); then
    echo "ERROR: run-task failed for ${name}." >&2
    overall=1
    continue
  fi

  if [ -z "${task_arn}" ] || [ "${task_arn}" = "None" ]; then
    echo "ERROR: run-task returned no task ARN for ${name}." >&2
    overall=1
    continue
  fi
  echo "  task started: ${task_arn}"
  echo "  waiting (oras pulls ~3 GB onto EFS; a few minutes)..."

  aws ecs wait tasks-stopped --cluster "${cluster}" --tasks "${task_arn}" --region "${REGION}" || true

  exit_code=$(aws ecs describe-tasks --cluster "${cluster}" --tasks "${task_arn}" --region "${REGION}" \
    --query 'tasks[0].containers[0].exitCode' --output text 2>/dev/null || echo "unknown")

  if [ "${exit_code}" != "0" ]; then
    reason=$(aws ecs describe-tasks --cluster "${cluster}" --tasks "${task_arn}" --region "${REGION}" \
      --query 'tasks[0].stoppedReason' --output text 2>/dev/null || true)
    echo "ERROR: sif-sync failed for ${name} (exitCode=${exit_code}, reason=${reason})." >&2
    echo "  logs: aws logs tail /aws/ecs/${PREFIX}/sif-sync --region ${REGION} --since 15m" >&2
    overall=1
    continue
  fi
  echo "  OK — ${name} staged on EFS /singularity (exitCode=0)."
done

if [ "${overall}" != "0" ]; then
  echo "Bootstrap FAILED — one or more SIFs did not stage (see errors above)." >&2
  exit 1
fi

echo "Bootstrap OK — all workload SIFs staged on EFS /singularity."
