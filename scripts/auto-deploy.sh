#!/usr/bin/env bash
# Pull-based deploy: ship origin/$DEPLOY_BRANCH once its CI run is green.
# Run by lexilingo-auto-deploy.timer inside the prod container.
# See docs/operations/AUTO_DEPLOY.md for the design and the incident it guards against.
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-InfinityZero3000/LexiLingo}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-dev}"
CI_WORKFLOW="${CI_WORKFLOW:-ci.yml}"
PROJECT_ROOT="${PROJECT_ROOT:-/opt/lexilingo}"
STATE_DIR="${STATE_DIR:-/var/lib/lexilingo/auto-deploy}"
MIN_FREE_GB="${MIN_FREE_GB:-5}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-300}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
DRY_RUN="${DRY_RUN:-false}"

CORE_CONTAINERS="lexilingo-gateway lexilingo-postgres lexilingo-mongodb lexilingo-redis lexilingo-backend-service lexilingo-reminder-worker lexilingo-reminder-beat lexilingo-ai-service"

log() { printf '[auto-deploy] %s\n' "$*"; }

run() {
  if [[ "${DRY_RUN}" == true ]]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

compose() {
  docker compose --env-file .env.production --env-file .env.production.secrets -f docker-compose.yml "$@"
}

# stdin: GitHub "workflow runs" JSON. stdout: "green|pending|red <sha>" or "none".
# Only the newest run counts: an older green run must not ship while a newer one is red or running.
ci_verdict() {
  jq -r '
    (.workflow_runs // []) | sort_by(.created_at) | last
    | if . == null then "none"
      elif .status != "completed" then "pending \(.head_sha)"
      elif .conclusion == "success" then "green \(.head_sha)"
      else "red \(.head_sha)" end'
}

# stdin: changed paths, one per line. stdout: compose services that need a rebuild.
# Worker and beat build from the backend context but are separate images, so they move together.
services_for_changes() {
  local backend=0 ai=0 path
  while IFS= read -r path; do
    case "${path}" in
      */tests/*|*.md) continue ;;
      backend-service/*) backend=1 ;;
      ai-service/*) ai=1 ;;
    esac
  done
  local out=""
  if [[ "${backend}" == 1 ]]; then out="backend-service backend-reminder-worker backend-reminder-beat"; fi
  if [[ "${ai}" == 1 ]]; then out="${out:+${out} }ai-service"; fi
  printf '%s\n' "${out}"
}

# Changes this script cannot apply by rebuilding a service; a human has to roll them out.
infra_changed() {
  grep -qE '^(docker-compose\.yml|gateway/|\.env\.production)' && return 0
  return 1
}

alert() {
  local key="$1" message="$2"
  log "ALERT: ${message}"
  logger -p user.crit -t lexilingo-auto-deploy "${message}" 2>/dev/null || true
  # Same condition on every 2-minute tick would flood the webhook; announce each distinct key once.
  if [[ -f "${STATE_DIR}/alerted_key" && "$(cat "${STATE_DIR}/alerted_key")" == "${key}" ]]; then
    return 0
  fi
  printf '%s' "${key}" > "${STATE_DIR}/alerted_key"
  printf 'timestamp_utc=%s\nmessage=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${message}" > "${STATE_DIR}/LAST_ALERT"
  if [[ -n "${ALERT_WEBHOOK_URL}" ]]; then
    curl -sS -m 15 -X POST -H 'Content-Type: application/json' \
      -d "{\"text\":\"LexiLingo auto-deploy: ${message}\"}" "${ALERT_WEBHOOK_URL}" >/dev/null 2>&1 || true
  fi
}

fetch_ci_runs() {
  local url="https://api.github.com/repos/${REPO_SLUG}/actions/workflows/${CI_WORKFLOW}/runs?branch=${DEPLOY_BRANCH}&event=push&per_page=5"
  local body="${STATE_DIR}/ci_runs.json" etag="${STATE_DIR}/ci_runs.etag" hdr code
  local -a extra=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then extra+=(-H "Authorization: Bearer ${GITHUB_TOKEN}"); fi
  # A 304 does not count against the unauthenticated 60 requests/hour limit, which a 2-minute poll would otherwise eat.
  if [[ -s "${etag}" && -s "${body}" ]]; then extra+=(-H "If-None-Match: $(cat "${etag}")"); fi
  hdr="$(mktemp)"
  code="$(curl -sS -m 20 -o "${body}.new" -D "${hdr}" -w '%{http_code}' \
    -H 'Accept: application/vnd.github+json' "${extra[@]}" "${url}" 2>/dev/null)" || code=000
  case "${code}" in
    200) mv "${body}.new" "${body}"; grep -i '^etag:' "${hdr}" | tr -d '\r' | cut -d' ' -f2- > "${etag}" || true ;;
    304) rm -f "${body}.new" ;;
    *) rm -f "${body}.new" "${hdr}"; log "GitHub API answered ${code}; will retry next tick"; return 1 ;;
  esac
  rm -f "${hdr}"
  cat "${body}"
}

preflight() {
  # btrfs needs room for metadata: at 97% even `docker rmi` fails, so free space has to exist before the build, not after.
  local free_gb
  free_gb="$(df --output=avail -BG / | tail -n 1 | tr -dc '0-9')"
  if (( free_gb < MIN_FREE_GB )); then
    alert "disk:${free_gb}" "only ${free_gb}GB free on / (need ${MIN_FREE_GB}GB); not building"
    return 1
  fi
  local down
  down="$(docker ps -a --filter status=exited --filter status=created --filter status=dead --format '{{.Names}}' | grep '^lexilingo-' | tr '\n' ' ' || true)"
  if [[ -n "${down}" ]]; then
    alert "down:${down}" "containers not running before deploy: ${down}; fix them first"
    return 1
  fi
  return 0
}

probe_tcp() {
  docker exec -i lexilingo-backend-service python - "$1" <<'PY'
import socket, sys
host, port = sys.argv[1].split(":")
s = socket.socket(); s.settimeout(5)
s.connect((host, int(port)))
PY
}

wait_healthy() {
  local name="$1" deadline=$(( $(date +%s) + HEALTH_TIMEOUT_SEC )) state
  while (( $(date +%s) < deadline )); do
    state="$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "${name}" 2>/dev/null || echo missing)"
    if [[ "${state}" == "running healthy" ]]; then return 0; fi
    sleep 5
  done
  log "${name} not healthy after ${HEALTH_TIMEOUT_SEC}s (${state})"
  return 1
}

# Every core container, not just the rebuilt ones: on 2026-11-13 a swap of three
# services left postgres without a network and mongodb dead, and only a probe from backend showed it.
verify_stack() {
  local name nets target
  for name in ${CORE_CONTAINERS}; do
    wait_healthy "${name}" || return 1
    nets="$(docker inspect -f '{{len .NetworkSettings.Networks}}' "${name}")"
    if (( nets < 1 )); then log "${name} has no network attached"; return 1; fi
  done
  for target in postgres:5432 mongodb:27017 redis:6379; do
    probe_tcp "${target}" || { log "backend-service cannot reach ${target}"; return 1; }
  done
  local attempt
  for attempt in 1 2; do
    if ./scripts/smoke-prod.sh >/dev/null 2>&1; then return 0; fi
    sleep 15
  done
  log "smoke test failed"
  return 1
}

rollback() {
  local services="$1" svc restored=""
  for svc in ${services}; do
    if docker image inspect "lexilingo-${svc}:rollback" >/dev/null 2>&1; then
      docker tag "lexilingo-${svc}:rollback" "lexilingo-${svc}:latest"
      restored="${restored} ${svc}"
    fi
  done
  if [[ -z "${restored}" ]]; then log "no rollback image to restore"; return 1; fi
  # The retag changes the image id, so compose recreates the container without --force-recreate.
  # shellcheck disable=SC2086
  compose up -d --no-deps ${restored}
  verify_stack
}

deploy() {
  local sha="$1" services="$2" svc
  for svc in ${services}; do
    if docker image inspect "lexilingo-${svc}:latest" >/dev/null 2>&1; then
      run docker tag "lexilingo-${svc}:latest" "lexilingo-${svc}:rollback"
    else
      log "WARNING: lexilingo-${svc}:latest missing, no rollback image for ${svc}"
    fi
  done
  # No `timeout` around a build: a cancelled llama-cpp-python build once left :latest pointing at nothing.
  # shellcheck disable=SC2086
  run compose build ${services}
  # --no-deps: only the rebuilt services restart; the databases are never touched.
  # shellcheck disable=SC2086
  run compose up -d --no-deps ${services}
  if [[ "${DRY_RUN}" == true ]]; then return 0; fi
  if verify_stack; then return 0; fi
  log "verification failed for ${sha}; rolling back ${services}"
  if rollback "${services}"; then
    alert "rolled-back:${sha}" "deploy of ${sha} failed verification; rolled back to the previous images and the stack is healthy"
  else
    alert "rollback-failed:${sha}" "deploy of ${sha} failed AND rollback did not restore a healthy stack; needs a human now"
  fi
  return 1
}

main() {
  mkdir -p "${STATE_DIR}"
  exec 9>"${STATE_DIR}/lock"
  flock -n 9 || { log "another run holds the lock"; exit 0; }
  cd "${PROJECT_ROOT}"

  local runs verdict sha last changed services
  runs="$(fetch_ci_runs)" || exit 0
  verdict="$(printf '%s' "${runs}" | ci_verdict)"
  case "${verdict}" in
    none*|pending*) log "CI not finished (${verdict}); waiting"; exit 0 ;;
    red*) log "CI is red for ${verdict#red }; not deploying"; exit 0 ;;
  esac
  sha="${verdict#green }"

  last="$(cat "${STATE_DIR}/last_deployed" 2>/dev/null || git rev-parse HEAD)"
  if [[ "${sha}" == "${last}" ]]; then exit 0; fi
  if [[ -f "${STATE_DIR}/failed_sha" && "$(cat "${STATE_DIR}/failed_sha")" == "${sha}" ]]; then
    log "${sha} already failed once; waiting for a newer green commit"
    exit 0
  fi

  git fetch origin "${DEPLOY_BRANCH}" --quiet
  git cat-file -e "${sha}^{commit}" 2>/dev/null || { log "${sha} not on origin/${DEPLOY_BRANCH}"; exit 0; }
  if ! git merge-base --is-ancestor "${last}" "${sha}"; then
    alert "not-ff:${sha}" "${sha} does not descend from the deployed ${last} (force-push?); deploy by hand"
    exit 1
  fi

  changed="$(git diff --name-only "${last}" "${sha}")"
  services="$(services_for_changes <<<"${changed}")"
  if infra_changed <<<"${changed}"; then
    log "NOTE: compose/gateway/env files changed; the new definitions apply only to rebuilt services, the rest needs a manual deploy"
  fi

  if [[ -n "${services}" ]]; then
    preflight || exit 1
  fi

  if [[ "$(git rev-parse HEAD)" != "${sha}" ]]; then
    # Local edits on the box (e.g. the gateway template) are kept; a conflict with them stops here.
    run git merge --ff-only "${sha}" || { alert "merge:${sha}" "cannot fast-forward the checkout to ${sha}; local changes conflict"; exit 1; }
  fi

  if [[ -z "${services}" ]]; then
    log "${sha}: no backend or ai-service change, checkout updated only"
    if [[ "${DRY_RUN}" != true ]]; then printf '%s' "${sha}" > "${STATE_DIR}/last_deployed"; fi
    exit 0
  fi

  log "deploying ${sha}: ${services}"
  if deploy "${sha}" "${services}"; then
    if [[ "${DRY_RUN}" != true ]]; then
      printf '%s' "${sha}" > "${STATE_DIR}/last_deployed"
      rm -f "${STATE_DIR}/failed_sha" "${STATE_DIR}/alerted_key"
    fi
    log "deployed ${sha}"
    exit 0
  fi
  if [[ "${DRY_RUN}" != true ]]; then printf '%s' "${sha}" > "${STATE_DIR}/failed_sha"; fi
  exit 1
}

# The braces make bash parse the whole call before running it, so editing this file during a run is harmless.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  { main "$@"; exit $?; }
fi
