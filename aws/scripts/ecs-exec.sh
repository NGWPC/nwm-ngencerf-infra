#!/usr/bin/env bash
#
# ecs-exec.sh: interactive or direct helper to execute into ngencerf Django container.
#
# Usage:
#   bash aws/scripts/ecs-exec.sh                     # Interactive menus for env & command
#   bash aws/scripts/ecs-exec.sh <env>               # Default: drops into dbshell for <env>
#   bash aws/scripts/ecs-exec.sh <env> [dbshell|bash|shell|<custom-command>]
#
# Examples:
#   bash aws/scripts/ecs-exec.sh ea dbshell          # Run PostgreSQL dbshell in ea
#   bash aws/scripts/ecs-exec.sh uat2 bash           # Open interactive bash in uat2
#   bash aws/scripts/ecs-exec.sh sandbox shell       # Open Django Python shell in sandbox
#

set -euo pipefail

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  cat <<'EOF'
Usage:
  bash aws/scripts/ecs-exec.sh                     # Interactive prompts for env and command
  bash aws/scripts/ecs-exec.sh <env>               # Default: drops into dbshell for <env>
  bash aws/scripts/ecs-exec.sh <env> [dbshell|bash|shell|<custom-command>]

Supported Envs:
  ea, uat2, sandbox

Modes:
  dbshell  - PostgreSQL interactive CLI (python manage.py dbshell) [Default]
  bash     - Interactive container shell (/bin/bash)
  shell    - Django ORM Python shell (python manage.py shell)
  <custom> - Any arbitrary command to run in the container
EOF
  exit 0
fi

# --- 1. Environment Selection ---
ENV="${1:-}"

if [ -z "${ENV}" ]; then
  echo "============================================================"
  echo "         ngenCERF Django Container Exec Helper"
  echo "============================================================"
  echo "Select an environment to connect to:"
  echo "  1) ea      (Customer acceptance / Test account)"
  echo "  2) uat2    (Customer acceptance / Test account)"
  echo "  3) sandbox (Development / Sandbox account)"
  echo ""
  read -r -p "Enter choice [1-3, default: 1]: " ENV_CHOICE
  case "${ENV_CHOICE:-1}" in
    1|ea)      ENV="ea" ;;
    2|uat2)    ENV="uat2" ;;
    3|sandbox) ENV="sandbox" ;;
    *)
      echo "Invalid selection. Exiting." >&2
      exit 1
      ;;
  esac
fi

# Region resolution: defaults to us-east-1 or env var; reads terraform only if initialized
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
DIR="${REPO_ROOT}/aws/envs/${ENV}"
if command -v terraform >/dev/null 2>&1 && [ -d "${DIR}/.terraform" ]; then
  tf_region="$(terraform -chdir="${DIR}" output -raw aws_region 2>/dev/null || true)"
  [ -n "${tf_region}" ] && [ "${tf_region}" != "None" ] && REGION="${tf_region}"
fi

PREFIX="ngencerf-$(echo "${ENV}" | tr '/' '-')"
CLUSTER="${PREFIX}-cluster"
SERVICE="${PREFIX}-django"
CONTAINER="django"

# --- 2. Action / Command Selection ---
MODE="${2:-}"

if [ -z "${MODE}" ]; then
  echo ""
  echo "Select command mode for ${ENV}:"
  echo "  1) Database Shell (python manage.py dbshell) [Default]"
  echo "  2) Interactive Bash Shell (/bin/bash)"
  echo "  3) Django Python Shell (python manage.py shell)"
  echo "  4) Custom command"
  echo ""
  read -r -p "Enter choice [1-4, default: 1]: " MODE_CHOICE
  case "${MODE_CHOICE:-1}" in
    1|dbshell) MODE="dbshell" ;;
    2|bash)    MODE="bash" ;;
    3|shell)   MODE="shell" ;;
    4|custom)
      read -r -p "Enter custom command to run: " CUSTOM_CMD
      MODE="${CUSTOM_CMD}"
      ;;
    *)
      echo "Invalid selection. Defaulting to dbshell."
      MODE="dbshell"
      ;;
  esac
fi

case "${MODE}" in
  dbshell)
    EXEC_CMD="bash -c 'if ! command -v psql >/dev/null 2>&1; then echo \"[Notice] psql not found in container. Attempting quick install...\"; if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq postgresql-client 2>/dev/null || true; elif command -v dnf >/dev/null 2>&1; then dnf install -y -q postgresql 2>/dev/null || true; elif command -v yum >/dev/null 2>&1; then yum install -y -q postgresql 2>/dev/null || true; elif command -v apk >/dev/null 2>&1; then apk add --no-cache postgresql-client 2>/dev/null || true; fi; fi; if command -v psql >/dev/null 2>&1; then exec python manage.py dbshell; else echo \"[Warning] psql could not be installed automatically. Launching Django Python shell instead (query models or via connection.cursor())...\"; exec python manage.py shell; fi'"
    ;;
  bash)
    EXEC_CMD="/bin/bash"
    ;;
  shell)
    EXEC_CMD="python manage.py shell"
    ;;
  *)
    EXEC_CMD="${MODE}"
    ;;
esac

# --- 3. Prerequisites Check ---
if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v session-manager-plugin >/dev/null 2>&1; then
  echo "WARNING: 'session-manager-plugin' was not found in your PATH." >&2
  echo "AWS ECS execute-command requires the Session Manager plugin." >&2
  echo "If this command fails, install the plugin from:" >&2
  echo "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html" >&2
  echo ""
fi

# Check AWS caller identity
echo "Connecting using AWS identity: $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo 'Unknown (check credentials)')"
echo "Target: ${CLUSTER} -> ${SERVICE} -> ${CONTAINER} (${REGION})"

# --- 4. Resolve Running Task ---
echo -n "Looking up running task for ${SERVICE}... "
TASK_ARN=$(aws ecs list-tasks \
  --region "${REGION}" \
  --cluster "${CLUSTER}" \
  --service-name "${SERVICE}" \
  --desired-status RUNNING \
  --query 'taskArns[0]' \
  --output text 2>/dev/null || true)

if [ -z "${TASK_ARN}" ] || [ "${TASK_ARN}" = "None" ]; then
  echo "FAILED" >&2
  echo "ERROR: No RUNNING task found for service '${SERVICE}' in cluster '${CLUSTER}' (${REGION})." >&2
  echo "Ensure the ECS service is deployed and running." >&2
  exit 1
fi

TASK_ID="${TASK_ARN##*/}"
echo "Found task ${TASK_ID}"
echo ""
echo "=== Executing '${EXEC_CMD}' in ${ENV} container '${CONTAINER}' ==="
echo "Tip: Type 'exit' or press Ctrl+D when finished."
echo ""

# --- 5. Start ECS Exec Session ---
exec aws ecs execute-command \
  --region "${REGION}" \
  --cluster "${CLUSTER}" \
  --task "${TASK_ARN}" \
  --container "${CONTAINER}" \
  --interactive \
  --command "${EXEC_CMD}"
