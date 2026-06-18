#!/usr/bin/env bash
#
# bootstrap.sh — one-time-per-bring-up EFS staging (SIFs + ngen static data).
#
# Runs the standalone bootstrap ECS tasks that seed a freshly created (empty) EFS:
#   - sif-sync (sif_sync.tf): one task per var.sif_workloads, oras-pulling each
#     pinned SIF onto EFS /singularity and repointing the <name>.sif symlink.
#   - static-data (static_data.tf): one task that `aws s3 sync`s the ngen
#     static-input tree from ngwpc-dev onto EFS /data/ngen-cal-data/ngen-static-files.
#
# Run it once after the first `terraform apply` for an env, and again after any
# cold bring-up (a fresh EFS is empty). Idempotent.
#
# Usage:
#   make bootstrap ENV=<env>          # both stages (default)
#   make load-static ENV=<env>        # static-data stage only
#   bash aws/scripts/bootstrap.sh <env> [all|sifs|static]
#
# Requires: AWS credentials for the target account, the env already
# `terraform apply`-ed, and jq.

set -euo pipefail

ENV="${1:?usage: bootstrap.sh <env> [all|sifs|static]  (e.g. sandbox)}"
STAGE="${2:-all}"
REGION="us-east-1"
DIR="aws/envs/${ENV}"
PREFIX="ngencerf-$(echo "${ENV}" | tr '/' '-')"

case "${STAGE}" in
  all | sifs | static) ;;
  *)
    echo "ERROR: stage must be all, sifs, or static (got '${STAGE}')." >&2
    exit 1
    ;;
esac

if [ ! -d "${DIR}" ]; then
  echo "ERROR: env dir '${DIR}' not found (run from the repo root)." >&2
  exit 1
fi
cd "${DIR}"

cluster=$(terraform output -raw ecs_cluster_name 2>/dev/null || true)
subnets=$(terraform output -json private_subnet_ids 2>/dev/null | jq -r 'join(",")' || true)

if [ -z "${cluster}" ] || [ -z "${subnets}" ]; then
  echo "ERROR: cluster/subnet outputs missing for env '${ENV}'. Is the env applied?" >&2
  exit 1
fi

# Run one standalone task to completion on a given SG. Returns non-zero on
# failure (so callers can keep going and surface an overall failure at the end).
# Args: <label> <task-definition> <security-group-id> <log-suffix>
run_task() {
  local label="$1" taskdef="$2" sg="$3" logsuffix="$4"
  local netcfg task_arn exit_code reason
  netcfg="awsvpcConfiguration={subnets=[${subnets}],securityGroups=[${sg}],assignPublicIp=DISABLED}"
  echo "=== ${label}: running task '${taskdef}' on cluster '${cluster}' (env=${ENV}, region=${REGION})..."

  if ! task_arn=$(aws ecs run-task \
    --cluster "${cluster}" \
    --task-definition "${taskdef}" \
    --launch-type FARGATE \
    --region "${REGION}" \
    --network-configuration "${netcfg}" \
    --query 'tasks[0].taskArn' --output text) \
    || [ -z "${task_arn}" ] || [ "${task_arn}" = "None" ]; then
    echo "ERROR: run-task failed for ${label}." >&2
    return 1
  fi
  echo "  task started: ${task_arn}"
  echo "  waiting (runs to completion; a few minutes)..."

  aws ecs wait tasks-stopped --cluster "${cluster}" --tasks "${task_arn}" --region "${REGION}" || true

  exit_code=$(aws ecs describe-tasks --cluster "${cluster}" --tasks "${task_arn}" --region "${REGION}" \
    --query 'tasks[0].containers[0].exitCode' --output text 2>/dev/null || echo "unknown")

  if [ "${exit_code}" != "0" ]; then
    reason=$(aws ecs describe-tasks --cluster "${cluster}" --tasks "${task_arn}" --region "${REGION}" \
      --query 'tasks[0].stoppedReason' --output text 2>/dev/null || true)
    echo "ERROR: ${label} failed (exitCode=${exit_code}, reason=${reason})." >&2
    echo "  logs: aws logs tail /aws/ecs/${PREFIX}/${logsuffix} --region ${REGION} --since 30m" >&2
    return 1
  fi
  echo "  OK — ${label} (exitCode=0)."
}

overall=0

# Stage each workload's SIF with its own run-to-completion task. Sequential so a
# failure is clearly attributable; each is attempted regardless of the others.
if [ "${STAGE}" = "all" ] || [ "${STAGE}" = "sifs" ]; then
  taskdefs=$(terraform output -json sif_sync_task_definitions 2>/dev/null || echo '{}')
  sg=$(terraform output -raw sif_sync_security_group_id 2>/dev/null || true)
  names=$(echo "${taskdefs}" | jq -r 'keys[]' 2>/dev/null || true)

  if [ -z "${sg}" ] || [ "${sg}" = "null" ] || [ -z "${names}" ]; then
    echo "ERROR: sif-sync outputs missing for env '${ENV}'. Is enable_pcs = true and sif_workloads set?" >&2
    exit 1
  fi

  for name in ${names}; do
    taskdef=$(echo "${taskdefs}" | jq -r --arg n "${name}" '.[$n]')
    run_task "SIF ${name}" "${taskdef}" "${sg}" "sif-sync" || overall=1
  done
fi

# Sync the ngen static-input tree from ngwpc-dev onto EFS.
if [ "${STAGE}" = "all" ] || [ "${STAGE}" = "static" ]; then
  taskdef=$(terraform output -raw static_data_task_definition 2>/dev/null || true)
  sg=$(terraform output -raw static_data_security_group_id 2>/dev/null || true)

  if [ -z "${taskdef}" ] || [ "${taskdef}" = "null" ] || [ -z "${sg}" ] || [ "${sg}" = "null" ]; then
    echo "ERROR: static-data outputs missing for env '${ENV}'. Is enable_pcs = true and the env applied?" >&2
    exit 1
  fi

  run_task "static-data" "${taskdef}" "${sg}" "static-data" || overall=1
fi

if [ "${overall}" != "0" ]; then
  echo "Bootstrap FAILED — one or more stages did not complete (see errors above)." >&2
  exit 1
fi

echo "Bootstrap OK (stage=${STAGE})."
