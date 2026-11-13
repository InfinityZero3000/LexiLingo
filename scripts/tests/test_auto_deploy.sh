#!/usr/bin/env bash
# Checks the two decisions auto-deploy.sh makes before it touches production:
# "is CI green for the newest commit" and "which services does this diff rebuild".
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../auto-deploy.sh
source "${HERE}/../auto-deploy.sh"

fail=0
expect() {
  local name="$1" want="$2" got="$3"
  if [[ "${want}" == "${got}" ]]; then
    printf 'ok   %s\n' "${name}"
  else
    printf 'FAIL %s\n     want: %s\n     got:  %s\n' "${name}" "${want}" "${got}"
    fail=1
  fi
}

run_json() { printf '%s' "$1" | ci_verdict; }

expect "no runs" "none" "$(run_json '{"workflow_runs":[]}')"
expect "missing key" "none" "$(run_json '{}')"
expect "newest green" "green bbb" "$(run_json '{"workflow_runs":[
  {"created_at":"2026-11-13T10:00:00Z","status":"completed","conclusion":"success","head_sha":"aaa"},
  {"created_at":"2026-11-13T11:00:00Z","status":"completed","conclusion":"success","head_sha":"bbb"}]}')"
# An older green run must not ship while a newer one is still running or has failed.
expect "older green, newer running" "pending ccc" "$(run_json '{"workflow_runs":[
  {"created_at":"2026-11-13T10:00:00Z","status":"completed","conclusion":"success","head_sha":"aaa"},
  {"created_at":"2026-11-13T12:00:00Z","status":"in_progress","conclusion":null,"head_sha":"ccc"}]}')"
expect "older green, newer red" "red ddd" "$(run_json '{"workflow_runs":[
  {"created_at":"2026-11-13T10:00:00Z","status":"completed","conclusion":"success","head_sha":"aaa"},
  {"created_at":"2026-11-13T12:00:00Z","status":"completed","conclusion":"failure","head_sha":"ddd"}]}')"
expect "cancelled counts as red" "red eee" "$(run_json '{"workflow_runs":[
  {"created_at":"2026-11-13T12:00:00Z","status":"completed","conclusion":"cancelled","head_sha":"eee"}]}')"

expect "backend change" "backend-service backend-reminder-worker backend-reminder-beat" \
  "$(printf 'backend-service/app/main.py\n' | services_for_changes)"
expect "ai change" "ai-service" "$(printf 'ai-service/api/main.py\n' | services_for_changes)"
expect "both" "backend-service backend-reminder-worker backend-reminder-beat ai-service" \
  "$(printf 'ai-service/x.py\nbackend-service/requirements.txt\n' | services_for_changes)"
expect "flutter and admin only" "" "$(printf 'flutter-app/lib/a.dart\nadmin-service/src/b.tsx\n' | services_for_changes)"
expect "tests and docs do not rebuild" "" \
  "$(printf 'backend-service/tests/test_x.py\nai-service/README.md\nai-service/tests/y.py\n' | services_for_changes)"
expect "empty diff" "" "$(printf '' | services_for_changes)"

infra() { if infra_changed <<<"$1"; then echo yes; else echo no; fi; }
expect "compose change is flagged" "yes" "$(infra 'docker-compose.yml')"
expect "gateway change is flagged" "yes" "$(infra $'backend-service/a.py\ngateway/nginx/templates/default.conf.template')"
expect "app change is not" "no" "$(infra 'backend-service/a.py')"

exit "${fail}"
