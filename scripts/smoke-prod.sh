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

echo -e "${YELLOW}=== LexiLingo Production Smoke Test ===${NC}"
echo "Base URL: ${BASE_URL}"
echo

# Gateway health
check_status "Gateway Health" "/health" "200"
check_status "Gateway AI Health" "/ai-health" "200"

# Backend routes via gateway
check_status "News Categories" "/api/v1/news/categories" "200"
check_status "Auth Me (no token)" "/api/v1/auth/me" "401"

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
