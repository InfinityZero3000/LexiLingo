#!/usr/bin/env bash
# Pull-based deploy: once the newest CI run on $DEPLOY_BRANCH is green, run the images that run built.
# Nothing is compiled here. Run by lexilingo-auto-deploy.timer inside the prod container;
# design and incident history in docs/operations/AUTO_DEPLOY.md.
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-InfinityZero3000/LexiLingo}"
REGISTRY="${REGISTRY:-ghcr.io/infinityzero3000/lexilingo}"
DEPLOY_BRANCH="${DEPLOY_BRANCH:-dev}"
CI_WORKFLOW="${CI_WORKFLOW:-ci.yml}"
PROJECT_ROOT="${PROJECT_ROOT:-/opt/lexilingo}"
STATE_DIR="${STATE_DIR:-/var/lib/lexilingo/auto-deploy}"
HEALTH_TIMEOUT_SEC="${HEALTH_TIMEOUT_SEC:-300}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
DRY_RUN="${DRY_RUN:-false}"

APP_SERVICES="backend-service backend-reminder-worker backend-reminder-beat ai-service"
CORE_CONTAINERS="lexilingo-gateway lexilingo-postgres lexilingo-mongodb lexilingo-redis lexilingo-backend-service lexilingo-reminder-worker lexilingo-reminder-beat lexilingo-ai-service"

log() { printf '[auto-deploy] %s\n' "$*"; }

# Images from the registry, tags pinned by an image-tags.env file.
compose_img() {
  local tags="$1"; shift
  docker compose -f docker-compose.yml -f docker-compose.images.yml \
    --env-file .env.production --env-file .env.production.secrets --env-file "${tags}" "$@"
}

# The images built on this box before the registry existed; only used to undo the first switch.
compose_local() {
  docker compose -f docker-compose.yml --env-file .env.production --env-file .env.production.secrets "$@"
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

# stdin: changed paths, one per line. stdout: compose services to move to the new images.
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

# Changes a new image does not carry; a human rolls them out with deploy-one-shot.sh.
infra_changed() {
  grep -qE '^(docker-compose[^/]*\.yml|gateway/|\.env\.production)' && return 0
  return 1
}

# stdin: the current image-tags.env (empty on the first switch). stdout: the same file with the
# services being deployed moved to sha-<sha>. Untouched services keep their tag, so a backend-only
# commit never restarts ai-service (a cold start rebuilds its embedding index).
next_tags() {
  local services=" $1 " sha="$2" backend="" ai="" line
  while IFS= read -r line; do
    case "${line}" in
      BACKEND_TAG=*) backend="${line#BACKEND_TAG=}" ;;
      AI_TAG=*) ai="${line#AI_TAG=}" ;;
    esac
  done
  if [[ "${services}" == *" backend-service "* ]]; then backend="sha-${sha}"; fi
  if [[ "${services}" == *" ai-service "* ]]; then ai="sha-${sha}"; fi
  printf 'BACKEND_TAG=%s\nAI_TAG=%s\n' "${backend}" "${ai}"
}

refs_from_tags() {
  local file="$1" line refs=""
  [[ -f "${file}" ]] || return 0
  while IFS= read -r line; do
    case "${line}" in
      BACKEND_TAG=?*) refs="${refs} ${REGISTRY}/backend:${line#BACKEND_TAG=}" ;;
      AI_TAG=?*) refs="${refs} ${REGISTRY}/ai-service:${line#AI_TAG=}" ;;
    esac
  done < "${file}"
  printf '%s\n' "${refs# }"
}

# stdin: "repo:tag" of local registry images. $1: refs to keep. stdout: refs safe to delete.
stale_images() {
  local keep=" $1 " ref
  while IFS= read -r ref; do
    [[ -z "${ref}" ]] && continue
    [[ "${keep}" == *" ${ref} "* ]] || printf '%s\n' "${ref}"
  done
}

alert() {
  local key="$1" message="$2"
  log "ALERT: ${message}"
  logger -p user.crit -t lexilingo-auto-deploy "${message}" 2>/dev/null || true
  # The same condition on every 2-minute tick would flood the webhook; announce each distinct key once.
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
  local services="$1" need_gb=3 free_gb down
  # Pulling ai-service downloads ~1.5 GB and unpacks ~4 GB next to the running image.
  if [[ " ${services} " == *" ai-service "* ]]; then need_gb=8; fi
  # btrfs needs room for metadata: at 97% even `docker rmi` failed with ENOSPC (2026-11-13).
  free_gb="$(df --output=avail -BG / | tail -n 1 | tr -dc '0-9')"
  if (( free_gb < need_gb )); then
    alert "disk:${free_gb}" "only ${free_gb}GB free on / (need ${need_gb}GB for ${services}); not deploying"
    return 1
  fi
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

# Every core container, not just the swapped ones: on 2026-11-13 a swap of three services left
# postgres without a network and mongodb dead, and only a probe from backend showed it.
verify_stack() {
  local name nets target attempt
  for name in ${CORE_CONTAINERS}; do
    wait_healthy "${name}" || return 1
    nets="$(docker inspect -f '{{len .NetworkSettings.Networks}}' "${name}")"
    if (( nets < 1 )); then log "${name} has no network attached"; return 1; fi
  done
  for target in postgres:5432 mongodb:27017 redis:6379; do
    probe_tcp "${target}" || { log "backend-service cannot reach ${target}"; return 1; }
  done
  for attempt in 1 2; do
    if ./scripts/smoke-prod.sh >/dev/null 2>&1; then return 0; fi
    sleep 15
  done
  log "smoke test failed"
  return 1
}

prune_images() {
  local keep repo
  keep="$(refs_from_tags "${STATE_DIR}/image-tags.env") $(refs_from_tags "${STATE_DIR}/image-tags.env.prev")"
  for repo in "${REGISTRY}/backend" "${REGISTRY}/ai-service"; do
    docker images --format '{{.Repository}}:{{.Tag}}' "${repo}" | stale_images "${keep}" | xargs -r docker rmi >/dev/null 2>&1 || true
  done
  # Untagged layers only; an image a container uses is never removed.
  docker image prune -f >/dev/null 2>&1 || true
}

# Returns 0 deployed, 1 failed verification (rolled back), 2 could not pull (nothing touched).
deploy() {
  local sha="$1" services="$2" last="$3" tags="${STATE_DIR}/image-tags.env" new="${STATE_DIR}/image-tags.env.next" first=false
  [[ -s "${tags}" ]] || first=true
  next_tags "${services}" "${sha}" < <(cat "${tags}" 2>/dev/null || true) > "${new}"

  # Pull before touching anything: a failed download leaves the running containers as they were.
  # shellcheck disable=SC2086
  if ! compose_img "${new}" pull ${services}; then
    rm -f "${new}"
    alert "pull:${sha}" "could not pull images for ${sha} (${services}); nothing was changed"
    return 2
  fi
  # --no-deps: only these services restart, the databases are never touched. --no-build: never compile here.
  # shellcheck disable=SC2086
  compose_img "${new}" up -d --no-deps --no-build ${services}

  if verify_stack; then
    if [[ "${first}" == false ]]; then cp "${tags}" "${tags}.prev"; fi
    mv "${new}" "${tags}"
    prune_images
    return 0
  fi

  log "verification failed for ${sha}; rolling back ${services}"
  rm -f "${new}"
  # Config files (gateway, ai-service/data) go back with the images; --keep refuses rather than lose local edits.
  git reset --keep "${last}" || log "could not reset the checkout to ${last}; config stays at ${sha}"
  # shellcheck disable=SC2086
  if [[ "${first}" == true ]]; then
    compose_local up -d --no-deps --no-build ${services}
  else
    compose_img "${tags}" up -d --no-deps --no-build ${services}
  fi
  if verify_stack; then
    alert "rolled-back:${sha}" "deploy of ${sha} failed verification; rolled back and the stack is healthy"
  else
    alert "rollback-failed:${sha}" "deploy of ${sha} failed AND the rollback is not healthy; needs a human now"
  fi
  return 1
}

main() {
  mkdir -p "${STATE_DIR}"
  exec 9>"${STATE_DIR}/lock"
  flock -n 9 || { log "another run holds the lock"; exit 0; }
  cd "${PROJECT_ROOT}"

  local runs verdict sha last changed services first=false
  runs="$(fetch_ci_runs)" || exit 0
  verdict="$(ci_verdict <<<"${runs}")"
  case "${verdict}" in
    none*|pending*) log "CI not finished (${verdict}); waiting"; exit 0 ;;
    red*) log "CI is red for ${verdict#red }; not deploying"; exit 0 ;;
  esac
  sha="${verdict#green }"

  [[ -s "${STATE_DIR}/image-tags.env" ]] || first=true
  last="$(cat "${STATE_DIR}/last_deployed" 2>/dev/null || git rev-parse HEAD)"
  if [[ "${sha}" == "${last}" && "${first}" == false ]]; then exit 0; fi
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
  if [[ "${first}" == true ]]; then
    services="${APP_SERVICES}"   # first switch from locally built images: move everything once
  else
    services="$(services_for_changes <<<"${changed}")"
  fi
  if infra_changed <<<"${changed}"; then
    log "NOTE: compose/gateway/env files changed; images do not carry them, roll them out with deploy-one-shot.sh"
  fi

  if [[ "${DRY_RUN}" == true ]]; then
    log "dry run: would deploy ${sha} (first switch: ${first}) services: ${services:-none}"
    next_tags "${services}" "${sha}" < <(cat "${STATE_DIR}/image-tags.env" 2>/dev/null || true) | sed 's/^/[auto-deploy]   /'
    exit 0
  fi

  if [[ -n "${services}" ]]; then preflight "${services}" || exit 1; fi

  if [[ "$(git rev-parse HEAD)" != "${sha}" ]]; then
    # The checkout is config and data mounts only (gateway templates, ai-service/data); local edits are kept.
    git merge --ff-only --quiet "${sha}" || { alert "merge:${sha}" "cannot fast-forward the checkout to ${sha}; local changes conflict"; exit 1; }
  fi

  if [[ -z "${services}" ]]; then
    log "${sha}: no backend or ai-service change, checkout updated only"
    printf '%s' "${sha}" > "${STATE_DIR}/last_deployed"
    exit 0
  fi

  log "deploying ${sha}: ${services}"
  local rc=0
  deploy "${sha}" "${services}" "${last}" || rc=$?
  case "${rc}" in
    0)
      printf '%s' "${sha}" > "${STATE_DIR}/last_deployed"
      rm -f "${STATE_DIR}/failed_sha" "${STATE_DIR}/alerted_key"
      log "deployed ${sha}"
      exit 0 ;;
    2) exit 1 ;;   # pull failed: retry on the next tick, nothing to roll back
    *) printf '%s' "${sha}" > "${STATE_DIR}/failed_sha"; exit 1 ;;
  esac
}

# The braces make bash parse the whole call before running it, so a git pull that rewrites this file mid-run is harmless.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  { main "$@"; exit $?; }
fi
