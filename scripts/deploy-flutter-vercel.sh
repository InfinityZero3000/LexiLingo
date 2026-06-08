#!/bin/bash

###############################################################################
# Deploy Flutter Web App to Vercel (Production)
# Usage: bash scripts/deploy-flutter-vercel.sh
###############################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_DIR="$PROJECT_ROOT/flutter-app"
VERCEL_PROJECT_ID="${VERCEL_PROJECT_ID_FLUTTER:-${VERCEL_PROJECT_ID:-}}"
VERCEL_CLI_ARGS=(--prod --yes)

clear
printf "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}\n"
printf "${CYAN}║                                                          ║${NC}\n"
printf "${CYAN}║      🚀 Deploy LexiLingo Flutter App to Vercel          ║${NC}\n"
printf "${CYAN}║                                                          ║${NC}\n"
printf "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}\n\n"

cd "$FLUTTER_DIR"

printf "${BLUE}[1/7] Checking prerequisites...${NC}\n\n"

for cmd in flutter node npm vercel; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "${RED}✗${NC} Missing required command: %s\n" "$cmd"
    exit 1
  fi
done

printf "${GREEN}✓${NC} Flutter: %s\n" "$(flutter --version | head -n 1)"
printf "${GREEN}✓${NC} Node: %s\n" "$(node --version)"
printf "${GREEN}✓${NC} npm: %s\n" "$(npm --version)"
printf "${GREEN}✓${NC} Vercel CLI: %s\n\n" "$(vercel --version)"

if [[ -f ".vercel/project.json" ]]; then
  linked_project_id="$(grep -o '"projectId": "[^"]*"' .vercel/project.json | sed 's/.*"\([^"]*\)"/\1/' || true)"
  linked_org_id="$(grep -o '"orgId": "[^"]*"' .vercel/project.json | sed 's/.*"\([^"]*\)"/\1/' || true)"

  if [[ -z "${VERCEL_ORG_ID:-}" && -n "$linked_org_id" ]]; then
    VERCEL_ORG_ID="$linked_org_id"
  fi

  if [[ -z "$VERCEL_PROJECT_ID" && -n "$linked_project_id" ]]; then
    VERCEL_PROJECT_ID="$linked_project_id"
  fi
fi

if [[ -z "${VERCEL_ORG_ID:-}" ]]; then
  printf "${RED}✗${NC} Missing VERCEL_ORG_ID and unable to infer from .vercel/project.json\n"
  exit 1
fi

if [[ -z "$VERCEL_PROJECT_ID" ]]; then
  printf "${RED}✗${NC} Missing VERCEL_PROJECT_ID_FLUTTER (or VERCEL_PROJECT_ID) and unable to infer from .vercel/project.json\n"
  exit 1
fi

if [[ -n "${VERCEL_TOKEN:-}" ]]; then
  VERCEL_CLI_ARGS+=(--token "$VERCEL_TOKEN")
else
  if ! vercel whoami >/dev/null 2>&1; then
    printf "${RED}✗${NC} Not authenticated with Vercel CLI. Run: vercel login\n"
    exit 1
  fi
fi

if [[ -f ".vercel/project.json" ]]; then
  if [[ -n "$linked_project_id" && "$linked_project_id" != "$VERCEL_PROJECT_ID" ]]; then
    printf "${RED}✗${NC} Linked Vercel projectId mismatch\n"
    printf "  .vercel/project.json: %s\n" "$linked_project_id"
    printf "  env VERCEL_PROJECT_ID: %s\n" "$VERCEL_PROJECT_ID"
    exit 1
  fi

  if [[ -n "$linked_org_id" && "$linked_org_id" != "$VERCEL_ORG_ID" ]]; then
    printf "${RED}✗${NC} Linked Vercel orgId mismatch\n"
    printf "  .vercel/project.json: %s\n" "$linked_org_id"
    printf "  env VERCEL_ORG_ID: %s\n" "$VERCEL_ORG_ID"
    exit 1
  fi
fi

export VERCEL_PROJECT_ID
export VERCEL_ORG_ID

printf "${GREEN}✓${NC} Vercel target org: %s\n" "$VERCEL_ORG_ID"
printf "${GREEN}✓${NC} Vercel target project: %s\n\n" "$VERCEL_PROJECT_ID"

printf "${BLUE}[2/7] Validating production env files...${NC}\n\n"

required_files=(
  ".env.production"
  "vercel.json"
  "web/index.html"
  "lib/firebase_options.dart"
)

for f in "${required_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    printf "${RED}✗${NC} Missing required file: %s\n" "$f"
    exit 1
  fi
done

google_id_env="$(grep '^GOOGLE_SERVER_CLIENT_ID=' .env.production | cut -d '=' -f2- || true)"
google_id_meta="$(grep -o 'google-signin-client_id" content="[^"]*"' web/index.html | sed 's/.*content="\([^"]*\)"/\1/' || true)"
api_base_url="$(grep '^API_BASE_URL=' .env.production | cut -d '=' -f2- || true)"
ai_base_url="$(grep '^AI_SERVICE_URL=' .env.production | cut -d '=' -f2- || true)"

if [[ -z "$google_id_env" ]]; then
  printf "${RED}✗${NC} GOOGLE_SERVER_CLIENT_ID is missing in .env.production\n"
  exit 1
fi

if [[ -z "$google_id_meta" ]]; then
  printf "${RED}✗${NC} google-signin-client_id meta is missing in web/index.html\n"
  exit 1
fi

if [[ "$google_id_env" != "$google_id_meta" ]]; then
  printf "${RED}✗${NC} Google client ID mismatch\n"
  printf "  .env.production: %s\n" "$google_id_env"
  printf "  web/index.html : %s\n" "$google_id_meta"
  printf "${YELLOW}⚠${NC} Please sync IDs before deploying.\n"
  exit 1
fi

if [[ "$api_base_url" != "https://api.lexilingo.me/api/v1" ]]; then
  printf "${RED}✗${NC} API_BASE_URL must be https://api.lexilingo.me/api/v1 in .env.production\n"
  printf "  Current value: %s\n" "$api_base_url"
  exit 1
fi

if [[ "$ai_base_url" != "https://api.lexilingo.me/api/v1" ]]; then
  printf "${RED}✗${NC} AI_SERVICE_URL must be https://api.lexilingo.me/api/v1 in .env.production\n"
  printf "  Current value: %s\n" "$ai_base_url"
  exit 1
fi

printf "${GREEN}✓${NC} .env.production exists and Google client ID is synchronized\n\n"

cat > assets/env/prod_config <<EOF
ENVIRONMENT=production
API_BASE_URL=${api_base_url}
API_BASE_URL_FALLBACK=
AI_SERVICE_URL=${ai_base_url}
AI_SERVICE_URL_FALLBACK=
ENABLE_VOICE_FEATURE=true
ENABLE_GAMIFICATION=true
ENABLE_STARTER_REWARD=false
DEBUG_MODE=false
GOOGLE_SERVER_CLIENT_ID=${google_id_env}
EOF

printf "${GREEN}✓${NC} Public Flutter config generated without server secrets\n\n"

printf "${BLUE}[3/7] Installing JS dependencies for Vercel build hooks...${NC}\n\n"
if [[ -f package-lock.json ]]; then
  npm ci
else
  npm install
fi
printf "${GREEN}✓${NC} npm dependencies installed\n\n"

printf "${BLUE}[4/7] Building Flutter Web release (uses generated public config)...${NC}\n\n"
flutter clean
flutter pub get
flutter build web --release --no-tree-shake-icons

if [[ ! -f "build/web/index.html" ]]; then
  printf "${RED}✗${NC} Missing build/web/index.html after build\n"
  exit 1
fi

if [[ ! -f "build/web/assets/assets/env/prod_config" ]]; then
  printf "${RED}✗${NC} Missing build/web/assets/assets/env/prod_config (public env not bundled)\n"
  exit 1
fi

if [[ -f "build/web/assets/.env" || -f "build/web/assets/.env.production" ]]; then
  printf "${RED}✗${NC} Raw .env files were bundled into the web build\n"
  exit 1
fi

if grep -Fq 'vocabulary/collection?limit=1000' build/web/main.dart.js; then
  printf "${RED}✗${NC} Unsupported vocabulary collection limit found in production bundle\n"
  exit 1
fi

if ! grep -Fq 'vocabulary/collection?limit=100' build/web/main.dart.js; then
  printf "${RED}✗${NC} Expected vocabulary collection compatibility request is missing\n"
  exit 1
fi

printf "${GREEN}✓${NC} Flutter web release build completed\n\n"

printf "${BLUE}[5/7] Validating Vercel prebuilt prerequisites...${NC}\n\n"
npm run vercel-build
printf "${GREEN}✓${NC} Vercel build pre-check passed\n\n"

printf "${BLUE}[6/7] Generating Vercel prebuilt output...${NC}\n\n"
vercel build "${VERCEL_CLI_ARGS[@]}"
printf "${GREEN}✓${NC} Vercel prebuilt output generated\n\n"

printf "${BLUE}[7/7] Deploying to Vercel production (prebuilt)...${NC}\n\n"
deploy_output="$(vercel deploy --prebuilt "${VERCEL_CLI_ARGS[@]}" 2>&1)"
printf "%s\n" "$deploy_output"

deploy_url="$(printf "%s\n" "$deploy_output" | grep -Eo 'https://[^ ]+\.vercel\.app' | tail -n 1 || true)"

if [[ -n "$deploy_url" ]]; then
  printf "${GREEN}✓${NC} Deployment URL: %s\n" "$deploy_url"
fi

printf "\n${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║              ✅ Flutter Vercel Deploy Complete           ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n\n"

printf "${BLUE}Post-deploy quick checks:${NC}\n"
printf "  1. Open login page and test Google sign-in popup/redirect\n"
printf "  2. Confirm API base URL in browser console is production\n"
printf "  3. Verify Firebase authorized domains include lexilingo.me and www.lexilingo.me\n"
printf "  4. Verify Vercel project has custom domains lexilingo.me and www.lexilingo.me\n\n"
