#!/usr/bin/env bash
#
# ops.sh: operational helper for day-to-day management of ngenCERF ECS & PCS resources.
#
# Usage:
#   bash aws/scripts/ops.sh <env> <action> [args...]
#
# Actions:
#   ecs-restart [all|django|nuxt] - Force new deployment on ECS Fargate tasks
#   ecs-status                   - Show status, desired/running counts, and task defs
#   slurm-queue                  - Print current Slurm queue from login node (squeue)
#   slurm-cancel-all             - Cancel all running and pending Slurm jobs (scancel)
#   slurm-drain                  - Drain Slurm partitions before an update (scontrol)
#   slurm-resume                 - Resume Slurm partitions after an update (scontrol)
#   login-ssm                    - Open an interactive AWS SSM shell on the PCS login node
#

set -euo pipefail

ENV="${1:?usage: ops.sh <env> <action> [args]  (e.g. ops.sh sandbox slurm-queue)}"
ACTION="${2:?missing action: ecs-restart, ecs-status, slurm-queue, slurm-cancel-all, slurm-drain, slurm-resume, login-ssm}"
DIR="aws/envs/${ENV}"
PREFIX="ngencerf-$(echo "${ENV}" | tr '/' '-')"

if [ ! -d "${DIR}" ]; then
  echo "ERROR: env dir '${DIR}' not found (run from the repo root)." >&2
  exit 1
fi
cd "${DIR}"

REGION="$(terraform output -raw aws_region 2>/dev/null || echo "${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}")"

get_login_node() {
  local iid
  iid=$(aws ec2 describe-instances --region "${REGION}" \
    --filters "Name=tag:Name,Values=${PREFIX}-pcs-node" "Name=instance-type,Values=c6i.large" \
    "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || true)
  if [ -z "${iid}" ] || [ "${iid}" = "None" ]; then
    echo "ERROR: login node not found (running c6i.large tagged ${PREFIX}-pcs-node). Is PCS enabled/running?" >&2
    return 1
  fi
  echo "${iid}"
}

run_login_command() {
  local cmd="$1"
  local iid b64 cmd_id status

  iid=$(get_login_node) || return 1

  # base64 encode command to avoid shell escaping issues over SSM
  b64=$(printf '%s' "${cmd}" | base64 | tr -d '\n')

  cmd_id=$(aws ssm send-command --region "${REGION}" --instance-ids "${iid}" \
    --document-name AWS-RunShellScript \
    --parameters "commands=[\"echo ${b64} | base64 -d | bash\"]" \
    --query 'Command.CommandId' --output text 2>/dev/null || true)

  if [ -z "${cmd_id}" ] || [ "${cmd_id}" = "None" ]; then
    echo "ERROR: failed to send SSM command to login node." >&2
    return 1
  fi

  status="Pending"
  for _ in $(seq 1 60); do
    status=$(aws ssm get-command-invocation --region "${REGION}" \
      --command-id "${cmd_id}" --instance-id "${iid}" \
      --query 'Status' --output text 2>/dev/null || echo "Pending")
    case "${status}" in
      Success | Failed | Cancelled | TimedOut) break ;;
      *) sleep 1 ;;
    esac
  done

  aws ssm get-command-invocation --region "${REGION}" --command-id "${cmd_id}" --instance-id "${iid}" \
    --query 'StandardOutputContent' --output text 2>/dev/null || true

  if [ "${status}" != "Success" ]; then
    aws ssm get-command-invocation --region "${REGION}" --command-id "${cmd_id}" --instance-id "${iid}" \
      --query 'StandardErrorContent' --output text 2>/dev/null >&2 || true
    return 1
  fi
}

case "${ACTION}" in
  ecs-restart)
    svc_target="${3:-all}"
    echo "=== Forcing new deployment on ECS cluster: ${PREFIX}-cluster (${ENV}) ==="
    case "${svc_target}" in
      all)
        aws ecs update-service --region "${REGION}" --cluster "${PREFIX}-cluster" --service "${PREFIX}-django" --force-new-deployment >/dev/null
        echo "  Triggered force-new-deployment for ${PREFIX}-django"
        aws ecs update-service --region "${REGION}" --cluster "${PREFIX}-cluster" --service "${PREFIX}-nuxt" --force-new-deployment >/dev/null
        echo "  Triggered force-new-deployment for ${PREFIX}-nuxt"
        ;;
      django)
        aws ecs update-service --region "${REGION}" --cluster "${PREFIX}-cluster" --service "${PREFIX}-django" --force-new-deployment >/dev/null
        echo "  Triggered force-new-deployment for ${PREFIX}-django"
        ;;
      nuxt)
        aws ecs update-service --region "${REGION}" --cluster "${PREFIX}-cluster" --service "${PREFIX}-nuxt" --force-new-deployment >/dev/null
        echo "  Triggered force-new-deployment for ${PREFIX}-nuxt"
        ;;
      *)
        echo "ERROR: unknown service '${svc_target}' (use all, django, or nuxt)." >&2
        exit 1
        ;;
    esac
    echo "Done. Services are pulling fresh tasks/images."
    ;;

  ecs-status)
    echo "=== ECS Service Status: ${PREFIX}-cluster (${ENV}) ==="
    aws ecs describe-services --region "${REGION}" --cluster "${PREFIX}-cluster" \
      --services "${PREFIX}-django" "${PREFIX}-nuxt" \
      --query 'services[].[serviceName,status,desiredCount,runningCount,deployments[0].rolloutState,deployments[0].taskDefinition]' \
      --output table
    ;;

  slurm-queue)
    echo "=== Active Slurm Queue on ${PREFIX} (${ENV}) ==="
    run_login_command 'squeue -o "%.18i %.12P %.25j %.8u %.2t %.10M %.6D %R"'
    ;;

  slurm-cancel-all)
    echo "=== Cancelling active and pending Slurm jobs for ${ENV} ==="
    run_login_command 'scancel --state=RUNNING,PENDING -v || true; echo ""; squeue'
    ;;

  slurm-drain)
    echo "=== Draining Slurm partitions for maintenance (${ENV}) ==="
    run_login_command 'sudo scontrol update PartitionName=c5n-9xlarge,r8a-12xlarge State=DRAIN Reason="Maintenance/SIF update"; echo ""; sinfo'
    echo "Partitions drained. New job submissions will remain in PENDING state."
    ;;

  slurm-resume)
    echo "=== Resuming Slurm partitions (${ENV}) ==="
    run_login_command 'sudo scontrol update PartitionName=c5n-9xlarge,r8a-12xlarge State=RESUME; echo ""; sinfo'
    echo "Partitions resumed and ready to schedule jobs."
    ;;

  login-ssm)
    login_iid=$(get_login_node)
    echo "=== Opening SSM Session to PCS Login Node: ${login_iid} (${ENV}) ==="
    exec aws ssm start-session --region "${REGION}" --target "${login_iid}"
    ;;

  *)
    echo "ERROR: unknown action '${ACTION}'." >&2
    echo "Valid actions: ecs-restart, ecs-status, slurm-queue, slurm-cancel-all, slurm-drain, slurm-resume, login-ssm" >&2
    exit 1
    ;;
esac
