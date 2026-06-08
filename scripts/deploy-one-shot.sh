#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/docker-compose.production.yml"
ENV_FILE="${PROJECT_ROOT}/.env.production"
SECRET_ENV_FILE="${PROJECT_ROOT}/.env.production.secrets"
SMOKE_SCRIPT="${PROJECT_ROOT}/scripts/smoke-prod.sh"
DEPLOY_DIR="${PROJECT_ROOT}/.deploy"
DOCKER_COMPOSE_CMD="sudo docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.production.yml"

SKIP_GIT_PULL=false
SKIP_IMAGE_PULL=false
SKIP_SMOKE=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Usage: ./scripts/deploy-one-shot.sh [options]

Options:
  --skip-git-pull     Skip git fetch/pull step
  --skip-image-pull   Skip docker compose pull step
  --skip-smoke        Skip smoke test step
  --dry-run           Print commands but do not execute
  -h, --help          Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-git-pull)
      SKIP_GIT_PULL=true
      shift
      ;;
    --skip-image-pull)
      SKIP_IMAGE_PULL=true
      shift
      ;;
    --skip-smoke)
      SKIP_SMOKE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

mkdir -p "${DEPLOY_DIR}"

TIMESTAMP_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TIMESTAMP_SAFE="$(date -u +%Y%m%dT%H%M%SZ)"
ROLLBACK_SIGNAL_FILE="${DEPLOY_DIR}/ROLLBACK_REQUIRED_${TIMESTAMP_SAFE}.txt"
ROLLBACK_FLAG_FILE="${DEPLOY_DIR}/ROLLBACK_REQUIRED"
LAST_SUCCESS_FILE="${DEPLOY_DIR}/LAST_SUCCESS"

cd "${PROJECT_ROOT}"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
PREV_COMMIT="$(git rev-parse --short HEAD)"

log() {
  printf '[deploy-one-shot] %s\n' "$1"
}

run() {
  if [[ "${DRY_RUN}" == true ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    eval "$@"
  fi
}

write_rollback_signal() {
  local reason="$1"
  {
    echo "timestamp_utc=${TIMESTAMP_UTC}"
    echo "branch=${CURRENT_BRANCH}"
    echo "previous_commit=${PREV_COMMIT}"
    echo "current_commit=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "reason=${reason}"
    echo ""
    echo "Rollback suggestion:"
    echo "  git checkout ${PREV_COMMIT}"
    echo "  ${DOCKER_COMPOSE_CMD} up -d --remove-orphans"
    echo "  ./scripts/smoke-prod.sh"
  } > "${ROLLBACK_SIGNAL_FILE}"

  cp "${ROLLBACK_SIGNAL_FILE}" "${ROLLBACK_FLAG_FILE}"
}

on_error() {
  local exit_code=$?
  local failed_cmd="${BASH_COMMAND}"

  log "Deployment failed at command: ${failed_cmd}"
  write_rollback_signal "command_failed:${failed_cmd} (exit_code=${exit_code})"

  log "Rollback signal created: ${ROLLBACK_SIGNAL_FILE}"
  log "Rollback flag updated: ${ROLLBACK_FLAG_FILE}"
  exit "${exit_code}"
}

trap on_error ERR

check_prerequisites() {
  [[ -f "${COMPOSE_FILE}" ]] || { echo "Missing ${COMPOSE_FILE}"; exit 1; }
  [[ -f "${ENV_FILE}" ]] || { echo "Missing ${ENV_FILE}"; exit 1; }
  [[ -f "${SECRET_ENV_FILE}" ]] || { echo "Missing ${SECRET_ENV_FILE}. Copy from .env.production.secrets.example and fill real values."; exit 1; }
  [[ -x "${SMOKE_SCRIPT}" ]] || { echo "Smoke script is not executable: ${SMOKE_SCRIPT}"; exit 1; }
}

check_required_secrets() {
  local required_vars=(
    POSTGRES_PASSWORD
    SECRET_KEY
    REDIS_PASSWORD
  )

  local missing=()
  for var_name in "${required_vars[@]}"; do
    local value
    value="$(grep -E "^${var_name}=" "${SECRET_ENV_FILE}" | tail -n 1 | cut -d '=' -f 2-)"
    if [[ -z "${value}" ]]; then
      missing+=("${var_name}")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "Missing required secrets in ${SECRET_ENV_FILE}: ${missing[*]}"
    exit 1
  fi
}

wait_for_service() {
  local service="$1"
  local timeout_sec="$2"
  local start_time
  start_time="$(date +%s)"

  while true; do
    local container_id
    container_id="$(${DOCKER_COMPOSE_CMD} ps -q "${service}" | head -n 1)"

    if [[ -n "${container_id}" ]]; then
      local running
      running="$(sudo docker inspect -f '{{.State.Running}}' "${container_id}")"

      if [[ "${running}" == "true" ]]; then
        local health
        health="$(sudo docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${container_id}")"
        if [[ "${health}" == "healthy" || "${health}" == "none" ]]; then
          log "Service ${service} is ready (health=${health})"
          return 0
        fi
      fi
    fi

    local now
    now="$(date +%s)"
    if (( now - start_time >= timeout_sec )); then
      echo "Timeout waiting for service ${service}"
      ${DOCKER_COMPOSE_CMD} ps
      return 1
    fi

    sleep 3
  done
}

perform_git_pull() {
  run "git fetch origin"

  local upstream_ref
  if upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)"; then
    log "Using upstream ref: ${upstream_ref}"
    run "git pull --ff-only"
    return 0
  fi

  if git ls-remote --exit-code --heads origin "${CURRENT_BRANCH}" >/dev/null 2>&1; then
    log "No upstream configured, pulling origin/${CURRENT_BRANCH}"
    run "git pull --ff-only origin ${CURRENT_BRANCH}"
    return 0
  fi

  log "No remote tracking branch for '${CURRENT_BRANCH}', skipping git pull."
  log "Tip: set upstream with 'git branch --set-upstream-to origin/<branch> ${CURRENT_BRANCH}'"
}

main() {
  check_prerequisites
  check_required_secrets

  log "Starting one-shot deployment at ${TIMESTAMP_UTC}"
  log "Branch: ${CURRENT_BRANCH}"
  log "Current commit: ${PREV_COMMIT}"

  if [[ "${SKIP_GIT_PULL}" == false ]]; then
    log "Step 1/4: Git pull"
    perform_git_pull
  else
    log "Step 1/4: Skipped git pull"
  fi

  if [[ "${SKIP_IMAGE_PULL}" == false ]]; then
    log "Step 2/4: Docker image pull"
    run "${DOCKER_COMPOSE_CMD} pull"
  else
    log "Step 2/4: Skipped docker image pull"
  fi

  log "Step 3/4: Docker up with orphan cleanup"
  run "${DOCKER_COMPOSE_CMD} up -d --remove-orphans"

  if [[ "${DRY_RUN}" == false ]]; then
    wait_for_service "postgres" 180
    wait_for_service "mongodb" 180
    wait_for_service "redis" 180
    wait_for_service "ai-service" 300
    wait_for_service "backend-service" 300
    wait_for_service "gateway" 180

    log "Reloading gateway Nginx config to refresh upstream DNS resolutions..."
    run "${DOCKER_COMPOSE_CMD} exec -T gateway nginx -s reload"
  fi

  if [[ "${SKIP_SMOKE}" == false ]]; then
    log "Step 4/4: Smoke test"
    run "./scripts/smoke-prod.sh"
  else
    log "Step 4/4: Skipped smoke test"
  fi

  if [[ "${DRY_RUN}" == false ]]; then
    {
      echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "branch=${CURRENT_BRANCH}"
      echo "commit=$(git rev-parse --short HEAD)"
    } > "${LAST_SUCCESS_FILE}"
    rm -f "${ROLLBACK_FLAG_FILE}"
  fi

  log "Deployment completed successfully."
  if [[ "${DRY_RUN}" == false ]]; then
    log "Success marker: ${LAST_SUCCESS_FILE}"
  fi
}

main "$@"
