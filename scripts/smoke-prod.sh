#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${1:-https://api.lexilingo.me}"
BASE_URL="${BASE_URL%/}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

failures=0

check_status() {
  local name="$1"
  local path="$2"
  local expected="$3"
  local url="${BASE_URL}${path}"

  local code
  code=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' "$url" || echo "000")

  if [[ ",${expected}," == *",${code},"* ]]; then
    printf "${GREEN}[PASS]${NC} %-28s %s -> %s (expected: %s)\n" "$name" "$path" "$code" "$expected"
  else
    printf "${RED}[FAIL]${NC} %-28s %s -> %s (expected: %s)\n" "$name" "$path" "$code" "$expected"
    failures=$((failures + 1))
  fi
}

check_cors_preflight() {
  local origin="https://admin.lexilingo.me"
  local path method headers
  while read -r path method; do
    headers=$(curl -sS --max-time 20 -D - -o /dev/null -X OPTIONS "${BASE_URL}${path}" \
      -H "Origin: ${origin}" -H "Access-Control-Request-Method: ${method}" \
      -H "Access-Control-Request-Headers: authorization,content-type" || true)

    if printf '%s' "${headers}" | grep -Eqi '^HTTP/[0-9.]+ 204' \
      && printf '%s' "${headers}" | grep -Fqi "access-control-allow-origin: ${origin}" \
      && printf '%s' "${headers}" | grep -Fqi 'access-control-allow-credentials: true' \
      && printf '%s' "${headers}" | grep -Eqi '^access-control-allow-headers:.*(authorization.*content-type|content-type.*authorization)'; then
      printf "${GREEN}[PASS]${NC} %-28s %s\n" "Admin Login CORS" "OPTIONS ${path}"
    else
      printf "${RED}[FAIL]${NC} %-28s %s\n" "Admin Login CORS" "${path}: invalid preflight"
      failures=$((failures + 1))
    fi
  done <<'EOF'
/api/v1/auth/google POST
/api/v1/auth/refresh POST
/api/v1/auth/me GET
EOF

  headers=$(curl -sS --max-time 20 -D - -o /dev/null -X OPTIONS \
    "${BASE_URL}/api/v1/auth/google" -H 'Origin: https://attacker.example' \
    -H 'Access-Control-Request-Method: POST' || true)
  if printf '%s' "${headers}" | grep -Fqi 'access-control-allow-origin:'; then
    printf "${RED}[FAIL]${NC} %-28s %s\n" "Admin CORS Rejection" "untrusted origin allowed"
    failures=$((failures + 1))
  else
    printf "${GREEN}[PASS]${NC} %-28s %s\n" "Admin CORS Rejection" "untrusted origin blocked"
  fi
}

echo -e "${YELLOW}=== LexiLingo Production Smoke Test ===${NC}"
echo "Base URL: ${BASE_URL}"
echo

# Gateway health
check_status "Gateway Health" "/health" "200"
check_status "Gateway AI Health" "/ai-health" "200"

# Backend routes via gateway
check_status "News Categories" "/api/v1/news/categories" "200"
check_status "Auth Me (no token)" "/api/v1/auth/me" "401"
check_cors_preflight

# AI routes via gateway
check_status "TraceCAG Health" "/api/v1/ai/trace-cag/health" "200"

# Chat route via gateway (AI service)
check_status "Chat Session Messages" "/api/v1/chat/sessions/test/messages?limit=1" "200"

echo
if [[ "$failures" -eq 0 ]]; then
  echo -e "${GREEN}Smoke test passed.${NC}"
  exit 0
else
  echo -e "${RED}Smoke test failed: ${failures} check(s).${NC}"
  exit 1
fi
