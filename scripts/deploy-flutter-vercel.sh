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

printf "${BLUE}[3/7] Installing JS dependencies for Vercel build hooks...${NC}\n\n"
npm install
printf "${GREEN}✓${NC} npm dependencies installed\n\n"

printf "${BLUE}[4/7] Building Flutter Web release (uses .env.production)...${NC}\n\n"
flutter clean
flutter pub get
flutter build web --release --no-tree-shake-icons

if [[ ! -f "build/web/index.html" ]]; then
  printf "${RED}✗${NC} Missing build/web/index.html after build\n"
  exit 1
fi

if [[ ! -f "build/web/assets/.env.production" ]]; then
  printf "${RED}✗${NC} Missing build/web/assets/.env.production (env not bundled)\n"
  exit 1
fi

printf "${GREEN}✓${NC} Flutter web release build completed\n\n"

printf "${BLUE}[5/7] Validating Vercel prebuilt prerequisites...${NC}\n\n"
npm run vercel-build
printf "${GREEN}✓${NC} Vercel build pre-check passed\n\n"

printf "${BLUE}[6/7] Generating Vercel prebuilt output...${NC}\n\n"
vercel build --prod
printf "${GREEN}✓${NC} Vercel prebuilt output generated\n\n"

printf "${BLUE}[7/7] Deploying to Vercel production (prebuilt)...${NC}\n\n"
vercel deploy --prebuilt --prod

printf "\n${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║              ✅ Flutter Vercel Deploy Complete           ║${NC}\n"
printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n\n"

printf "${BLUE}Post-deploy quick checks:${NC}\n"
printf "  1. Open login page and test Google sign-in popup/redirect\n"
printf "  2. Confirm API base URL in browser console is production\n"
printf "  3. Verify Firebase authorized domains include lexilingo.me and www.lexilingo.me\n"
printf "  4. Verify Vercel project has custom domains lexilingo.me and www.lexilingo.me\n\n"
