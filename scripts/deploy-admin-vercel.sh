#!/bin/bash

###############################################################################
# Deploy Web Admin Dashboard to Vercel
# Usage: bash scripts/deploy-admin-vercel.sh
###############################################################################

set -e
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADMIN_DIR="$PROJECT_ROOT/admin-service"
ENV_FILE="${DEPLOY_ADMIN_ENV_FILE:-$ADMIN_DIR/.env.production}"

is_placeholder() {
    local value="${1:-}"
    [[ -z "$value" || "$value" == REPLACE_* || "$value" == *"REPLACE_WITH"* || "$value" == your-* || "$value" == *"your-"* ]]
}

env_value() {
    local key="$1"
    grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d '=' -f2-
}

mask_value() {
    local key="$1"
    local value="$2"

    if [[ "$key" =~ (KEY|TOKEN|SECRET|PASSWORD) ]]; then
        if [ ${#value} -le 8 ]; then
            echo "********"
        else
            echo "${value:0:4}********${value: -4}"
        fi
    else
        echo "$value"
    fi
}

print_env_config() {
    while IFS='=' read -r key value; do
        [ -z "$key" ] && continue
        echo "  $key=$(mask_value "$key" "$value")"
    done < <(grep "^VITE_" "$ENV_FILE")
}

validate_env_config() {
    local missing=0
    local use_gateway
    local use_gateway_lower
    use_gateway="$(env_value "VITE_USE_GATEWAY")"
    use_gateway_lower="$(printf '%s' "$use_gateway" | tr '[:upper:]' '[:lower:]')"

    local required_keys=(
        "VITE_ENV"
        "VITE_BACKEND_URL"
        "VITE_AI_URL"
        "VITE_GOOGLE_CLIENT_ID"
        "VITE_AI_ADMIN_URL"
    )

    for key in "${required_keys[@]}"; do
        local value
        value="$(env_value "$key")"
        if is_placeholder "$value"; then
            echo -e "${RED}✗${NC} $key is missing or still uses a placeholder"
            missing=1
        fi
    done

    if [[ "$use_gateway_lower" == "true" ]]; then
        local api_key
        api_key="$(env_value "VITE_API_KEY")"
        if is_placeholder "$api_key"; then
            echo -e "${RED}✗${NC} VITE_API_KEY is required when VITE_USE_GATEWAY=true"
            missing=1
        fi
    fi

    local ai_admin_key
    ai_admin_key="$(env_value "VITE_AI_ADMIN_API_KEY")"
    if ! is_placeholder "$ai_admin_key"; then
        echo -e "${YELLOW}⚠${NC} VITE_AI_ADMIN_API_KEY is browser-exposed. Prefer a server-side admin proxy before enabling it."
    fi

    if [ "$missing" -ne 0 ]; then
        echo ""
        echo -e "${YELLOW}Update $ENV_FILE, then run this script again.${NC}"
        exit 1
    fi
}

clear 2>/dev/null || true
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║      🚀 Deploy LexiLingo Admin Dashboard to Vercel      ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

cd "$ADMIN_DIR"

# Check prerequisites
echo -e "${BLUE}[1/5] Checking prerequisites...${NC}"
echo ""

if ! command -v node &> /dev/null; then
    echo -e "${RED}✗${NC} Node.js not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} Node.js: $(node --version)"

if ! command -v pnpm &> /dev/null; then
    echo -e "${RED}✗${NC} pnpm not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} pnpm: $(pnpm --version)"

# Check Vercel CLI
if ! command -v vercel &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Vercel CLI not found. Installing..."
    npm install -g vercel || pnpm add -g vercel
fi
echo -e "${GREEN}✓${NC} Vercel CLI: $(vercel --version)"

echo ""
echo -e "${BLUE}[2/5] Checking environment configuration...${NC}"
echo ""

# Check if .env.production exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}⚠${NC} .env.production not found. Creating..."
    cat > "$ENV_FILE" << 'EOF'
VITE_ENV=production
VITE_USE_GATEWAY=false
VITE_API_KEY=
VITE_AI_ADMIN_URL=https://api.lexilingo.me/api/v1/ai-admin
VITE_AI_ADMIN_API_KEY=
VITE_BACKEND_URL=https://api.lexilingo.me/api/v1
VITE_BACKEND_URL_FALLBACK=
VITE_AI_URL=https://api.lexilingo.me/api/v1
VITE_AI_URL_FALLBACK=
VITE_GOOGLE_CLIENT_ID=REPLACE_WITH_GOOGLE_CLIENT_ID
VITE_APP_NAME=LexiLingo Admin Dashboard
VITE_APP_VERSION=0.5.0
VITE_ADMIN_EMAILS=
VITE_SUPER_ADMIN_EMAILS=
EOF
    echo -e "${YELLOW}⚠${NC} Please update URLs in .env.production"
    echo ""
    read -p "Press Enter to continue..."
fi

echo -e "${GREEN}✓${NC} Environment configuration ready"
echo ""

# Show current config
echo -e "${BLUE}Current Configuration:${NC}"
print_env_config
echo ""

validate_env_config

if [ "${DEPLOY_ADMIN_ASSUME_YES:-0}" != "1" ]; then
    read -p "Is this configuration correct? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Please update $ENV_FILE and run again"
        exit 1
    fi
fi

echo ""
echo -e "${BLUE}[3/5] Installing dependencies...${NC}"
echo ""
CI=true pnpm install \
    --config.allowBuilds.esbuild=true \
    --config.confirmModulesPurge=false
echo -e "${GREEN}✓${NC} Dependencies installed"

echo ""
echo -e "${BLUE}[4/5] Building production bundle...${NC}"
echo ""

# Clean previous build
rm -rf dist

# Build with production env
pnpm build
if [ $? -ne 0 ]; then
    echo -e "${RED}✗${NC} pnpm build failed"
    exit 1
fi

if [ ! -d "dist" ]; then
    echo -e "${RED}✗${NC} Build failed (dist folder not found)"
    exit 1
fi

echo -e "${GREEN}✓${NC} Build completed"

# Show build stats
echo ""
echo -e "${BLUE}Build Statistics:${NC}"
echo "  Size: $(du -sh dist | cut -f1)"
echo "  Files: $(find dist -type f | wc -l | xargs)"
echo ""

echo -e "${BLUE}[5/5] Deploying to Vercel...${NC}"
echo ""

if [ "${DEPLOY_ADMIN_SKIP_VERCEL:-0}" = "1" ]; then
    echo -e "${YELLOW}⚠${NC} DEPLOY_ADMIN_SKIP_VERCEL=1, skipping Vercel production deploy"
else
    echo -e "${BLUE}→${NC} Deploying admin-service to Vercel production..."
    echo ""

    if ! vercel whoami >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠${NC} Vercel CLI is not logged in. Starting login..."
        vercel login
    fi

    vercel --prod --yes

    echo ""
    echo -e "${GREEN}✓${NC} Production deployment complete!"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ Deployment Process Complete! 🎉          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Update backend CORS settings if the admin domain changed:"
echo "     ALLOWED_ORIGINS=<frontend-url>,<admin-url>"
echo "  2. Test admin login"
echo "  3. Monitor deployment logs"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  ${CYAN}vercel --prod${NC}    - Deploy to production"
echo "  ${CYAN}vercel logs${NC}      - View deployment logs"
echo "  ${CYAN}vercel domains${NC}   - Manage custom domains"
echo ""
