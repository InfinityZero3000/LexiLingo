#!/usr/bin/env bash
# deploy-one-shot.sh must never build on the VPS: it runs the registry images pinned by
# image-tags.env, exactly like auto-deploy.sh, unless --bootstrap-local-build is passed.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/../deploy-one-shot.sh"

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" | sed 's/^/     /'; fail=1; }
expect_contains() { if grep -qF -- "$3" <<<"$2"; then ok "$1"; else bad "$1 (missing: $3)" "$2"; fi; }
expect_lacks() { if grep -qF -- "$3" <<<"$2"; then bad "$1 (found: $3)" "$2"; else ok "$1"; fi; }

# Static: every real '--build' sits inside bootstrap_up, the one flag-gated path.
stray="$(awk '
  /^bootstrap_up\(\) \{/ { in_fn=1 }
  { code=$0; sub(/^[ \t]*#.*/, "", code) }
  code ~ /--build([^-a-z]|$)/ && !in_fn { print NR": "$0 }
  in_fn && /^\}/ { in_fn=0 }
' "${SCRIPT}")"
if [[ -z "${stray}" ]]; then ok "--build only inside bootstrap_up"; else bad "--build outside bootstrap_up" "${stray}"; fi

# Every `up` the script runs carries --no-build, outside bootstrap_up.
nobuild="$(grep -nE '\$\{DOCKER_COMPOSE_CMD\} up' "${SCRIPT}" | grep -v -- '--no-build' || true)"
if [[ -z "${nobuild}" ]]; then ok "every up uses --no-build"; else bad "up without --no-build" "${nobuild}"; fi

# The default compose command names the override and the tags file.
default_cmd="$(grep -E '^DOCKER_COMPOSE_CMD=' "${SCRIPT}")"
expect_contains "default compose uses docker-compose.images.yml" "${default_cmd}" "-f docker-compose.images.yml"
expect_contains "default compose reads image-tags.env" "${default_cmd}" '--env-file ${TAGS_FILE}'

# Behavioural: run a copy against a scratch project with fake docker/sudo/flock.
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/proj/scripts" "${WORK}/bin" "${WORK}/state"
cp "${SCRIPT}" "${WORK}/proj/scripts/deploy-one-shot.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "${WORK}/proj/scripts/smoke-prod.sh"
chmod +x "${WORK}/proj/scripts/smoke-prod.sh" "${WORK}/proj/scripts/deploy-one-shot.sh"
: > "${WORK}/proj/docker-compose.yml"
: > "${WORK}/proj/docker-compose.images.yml"
printf 'ALLOWED_HOSTS=backend-service\n' > "${WORK}/proj/.env.production"
printf 'POSTGRES_PASSWORD=x\nSECRET_KEY=x\nREDIS_PASSWORD=x\nMONGO_ROOT_USER=x\nMONGO_ROOT_PASSWORD=x\nMONGO_APP_USER=x\nMONGO_APP_PASSWORD=x\nAI_AUDIT_INGEST_SECRET=x\n' > "${WORK}/proj/.env.production.secrets"
printf '#!/usr/bin/env bash\nexec "$@"\n' > "${WORK}/bin/sudo"
printf '#!/usr/bin/env bash\necho "docker $*"\n' > "${WORK}/bin/docker"
printf '#!/usr/bin/env bash\nexit 0\n' > "${WORK}/bin/flock"
chmod +x "${WORK}/bin/"*
(cd "${WORK}/proj" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init)

deploy() {
  (cd "${WORK}/proj" && PATH="${WORK}/bin:${PATH}" STATE_DIR="${WORK}/state" \
    bash scripts/deploy-one-shot.sh --skip-git-pull --skip-smoke "$@" 2>&1) || echo "EXIT=$?"
}

out="$(deploy --dry-run)"
expect_contains "refuses without image-tags.env" "${out}" "Missing ${WORK}/state/image-tags.env"
expect_contains "refusal exits non-zero" "${out}" "EXIT=1"
expect_lacks "refusal does not build" "${out}" "--build"
expect_lacks "refusal runs no compose" "${out}" "docker compose"

printf 'BACKEND_TAG=sha-a\nAI_TAG=sha-a\n' > "${WORK}/state/image-tags.env"
out="$(deploy --dry-run)"
expect_contains "uses the images override" "${out}" "-f docker-compose.yml -f docker-compose.images.yml"
expect_contains "reads the tags file" "${out}" "--env-file ${WORK}/state/image-tags.env"
expect_contains "up is --no-build" "${out}" "up -d --no-build --remove-orphans"
expect_contains "pre-flight prints the plan" "${out}" "Pre-flight"
expect_contains "pre-flight is up --dry-run" "${out}" "--no-build --remove-orphans --dry-run"
expect_lacks "never --build by default" "${out}" "up -d --build"
expect_lacks "no local rollback tagging" "${out}" "docker tag"

out="$(deploy --dry-run --bootstrap-local-build)"
expect_contains "bootstrap refused when tags exist" "${out}" "Refusing --bootstrap-local-build"
expect_lacks "refused bootstrap does not build" "${out}" "up -d --build"

rm -f "${WORK}/state/image-tags.env"
out="$(deploy --dry-run --bootstrap-local-build)"
expect_contains "bootstrap builds when explicit" "${out}" "up -d --build --remove-orphans"
expect_lacks "bootstrap skips the images override" "${out}" "docker-compose.images.yml"

exit "${fail}"
