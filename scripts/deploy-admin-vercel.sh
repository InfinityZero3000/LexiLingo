#!/bin/bash

###############################################################################
# Deploy Web Admin Dashboard to Vercel
# Usage: bash scripts/deploy-admin-vercel.sh
###############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADMIN_DIR="$PROJECT_ROOT/web-admin"

clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║      🚀 Deploy LexiLingo Admin Dashboard to Vercel      ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

cd "$ADMIN_DIR"

# Check prerequisites
echo -e "${BLUE}[1/6] Checking prerequisites...${NC}"
echo ""

if ! command -v node &> /dev/null; then
    echo -e "${RED}✗${NC} Node.js not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} Node.js: $(node --version)"

if ! command -v npm &> /dev/null; then
    echo -e "${RED}✗${NC} npm not found"
    exit 1
fi
echo -e "${GREEN}✓${NC} npm: $(npm --version)"

# Check Vercel CLI
if ! command -v vercel &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Vercel CLI not found. Installing..."
    npm install -g vercel
fi
echo -e "${GREEN}✓${NC} Vercel CLI: $(vercel --version)"

echo ""
echo -e "${BLUE}[2/6] Checking environment configuration...${NC}"
echo ""

# Check if .env.production exists
if [ ! -f ".env.production" ]; then
    echo -e "${YELLOW}⚠${NC} .env.production not found. Creating..."
    cat > .env.production << 'EOF'
VITE_BACKEND_URL=https://lexilingo-backend.onrender.com/api/v1
VITE_AI_URL=https://your-tunnel-url.trycloudflare.com/api/v1
VITE_APP_NAME=LexiLingo Admin Dashboard
VITE_APP_VERSION=0.5.0
VITE_ADMIN_EMAILS=thefirestar312@gmail.com
VITE_SUPER_ADMIN_EMAILS=nhthang312@gmail.com
EOF
    echo -e "${YELLOW}⚠${NC} Please update URLs in .env.production"
    echo ""
    read -p "Press Enter to continue..."
fi

echo -e "${GREEN}✓${NC} Environment configuration ready"
echo ""

# Show current config
echo -e "${BLUE}Current Configuration:${NC}"
grep "^VITE_" .env.production | while read line; do
    echo "  $line"
done
echo ""

read -p "Is this configuration correct? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Please update .env.production and run again"
    exit 1
fi

echo ""
echo -e "${BLUE}[3/6] Installing dependencies...${NC}"
echo ""
npm install
echo -e "${GREEN}✓${NC} Dependencies installed"

echo ""
echo -e "${BLUE}[4/6] Building production bundle...${NC}"
echo ""

# Clean previous build
rm -rf dist

# Build with production env
npm run build

if [ ! -d "dist" ]; then
    echo -e "${RED}✗${NC} Build failed"
    exit 1
fi

echo -e "${GREEN}✓${NC} Build completed"

# Show build stats
echo ""
echo -e "${BLUE}Build Statistics:${NC}"
echo "  Size: $(du -sh dist | cut -f1)"
echo "  Files: $(find dist -type f | wc -l | xargs)"
echo ""

echo -e "${BLUE}[5/6] Testing build locally...${NC}"
echo ""

# Start preview server
npm run preview > /dev/null 2>&1 &
PREVIEW_PID=$!
sleep 3

if curl -s -o /dev/null -w "%{http_code}" http://localhost:4173/ | grep -q "200"; then
    echo -e "${GREEN}✓${NC} Preview is running on http://localhost:4173/"
    echo ""
    echo "Opening in browser for quick review..."
    sleep 1
    open http://localhost:4173/ 2>/dev/null || xdg-open http://localhost:4173/ 2>/dev/null || true
    echo ""
    read -p "Preview looks good? Press Enter to deploy..."
    kill $PREVIEW_PID 2>/dev/null || true
else
    echo -e "${YELLOW}⚠${NC} Preview test skipped"
    kill $PREVIEW_PID 2>/dev/null || true
fi

echo ""
echo -e "${BLUE}[6/6] Deploying to Vercel...${NC}"
echo ""

echo "Choose deployment method:"
echo "  1. Deploy via Vercel CLI (fastest)"
echo "  2. Deploy via GitHub (auto-deploy on push)"
echo ""
read -p "Choose method (1-2): " -n 1 -r
echo

case $REPLY in
    1)
        echo ""
        echo -e "${BLUE}→${NC} Deploying via Vercel CLI..."
        echo ""
        
        # Login to Vercel
        vercel login
        
        echo ""
        echo "Deploying to production..."
        vercel --prod
        
        echo ""
        echo -e "${GREEN}✓${NC} Deployment complete!"
        echo ""
        echo "Your admin dashboard is now live!"
        echo ""
        ;;
    2)
        echo ""
        echo -e "${BLUE}→${NC} GitHub deployment setup"
        echo ""
        echo "To deploy via GitHub:"
        echo ""
        echo "1. Push your code to GitHub:"
        echo "   ${CYAN}git add .${NC}"
        echo "   ${CYAN}git commit -m \"Add admin dashboard\"${NC}"
        echo "   ${CYAN}git push origin main${NC}"
        echo ""
        echo "2. Go to https://vercel.com/new"
        echo ""
        echo "3. Import your repository"
        echo ""
        echo "4. Configure project:"
        echo "   - Framework Preset: Vite"
        echo "   - Root Directory: web-admin"
        echo "   - Build Command: npm run build"
        echo "   - Output Directory: dist"
        echo ""
        echo "5. Add Environment Variables (from .env.production):"
        grep "^VITE_" .env.production | while read line; do
            echo "   $line"
        done
        echo ""
        echo "6. Click 'Deploy'"
        echo ""
        read -p "Press Enter to open Vercel dashboard..."
        open "https://vercel.com/new" 2>/dev/null || xdg-open "https://vercel.com/new" 2>/dev/null || true
        ;;
    *)
        echo "Invalid option"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✅ Deployment Process Complete! 🎉          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "  1. Copy your Vercel URL"
echo "  2. Update backend CORS settings:"
echo "     ALLOWED_ORIGINS=<frontend-url>,<admin-url>"
echo "  3. Test admin login"
echo "  4. Monitor deployment logs"
echo ""
echo -e "${BLUE}Useful Commands:${NC}"
echo "  ${CYAN}vercel${NC}           - Deploy to preview"
echo "  ${CYAN}vercel --prod${NC}    - Deploy to production"
echo "  ${CYAN}vercel logs${NC}      - View deployment logs"
echo "  ${CYAN}vercel domains${NC}   - Manage custom domains"
echo ""
