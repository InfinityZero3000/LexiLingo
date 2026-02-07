#!/bin/bash

###############################################################################
# Deploy Web Admin Dashboard to Netlify
# Usage: bash scripts/deploy-admin.sh
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
echo -e "${CYAN}║      🚀 Deploy LexiLingo Admin Dashboard to Netlify     ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if in admin directory
cd "$ADMIN_DIR"

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗${NC} Node.js not found. Please install Node.js first."
    exit 1
fi
echo -e "${GREEN}✓${NC} Node.js: $(node --version)"

# Check npm
if ! command -v npm &> /dev/null; then
    echo -e "${RED}✗${NC} npm not found."
    exit 1
fi
echo -e "${GREEN}✓${NC} npm: $(npm --version)"

echo ""
echo -e "${BLUE}[1/5] Checking environment configuration...${NC}"
echo ""

# Check if .env.production exists
if [ ! -f ".env.production" ]; then
    echo -e "${YELLOW}⚠${NC} .env.production not found. Creating from example..."
    cp .env.example .env.production
    echo -e "${YELLOW}⚠${NC} Please update .env.production with your production URLs:"
    echo "  - VITE_BACKEND_URL (Render.com backend URL)"
    echo "  - VITE_AI_URL (Cloudflare tunnel URL)"
    echo ""
    read -p "Press Enter to edit .env.production, or Ctrl+C to exit..."
    ${EDITOR:-nano} .env.production
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
    echo "Please update .env.production and run this script again."
    exit 1
fi

echo ""
echo -e "${BLUE}[2/5] Installing dependencies...${NC}"
echo ""

npm install
echo -e "${GREEN}✓${NC} Dependencies installed"

echo ""
echo -e "${BLUE}[3/5] Building production bundle...${NC}"
echo ""

# Clean previous build
rm -rf dist

# Build
npm run build

if [ ! -d "dist" ]; then
    echo -e "${RED}✗${NC} Build failed - dist directory not found"
    exit 1
fi

echo -e "${GREEN}✓${NC} Build completed successfully"

# Show build stats
echo ""
echo -e "${BLUE}Build Statistics:${NC}"
du -sh dist
echo "Files:"
find dist -type f | wc -l | xargs echo "  Total files:"
find dist -name "*.js" | wc -l | xargs echo "  JavaScript files:"
find dist -name "*.css" | wc -l | xargs echo "  CSS files:"
echo ""

echo -e "${BLUE}[4/5] Testing build locally...${NC}"
echo ""

# Start preview server in background
npm run preview > /dev/null 2>&1 &
PREVIEW_PID=$!

sleep 3

# Test if preview server is running
if curl -s -o /dev/null -w "%{http_code}" http://localhost:4173/ | grep -q "200"; then
    echo -e "${GREEN}✓${NC} Preview server running on http://localhost:4173/"
    echo "  Opening in browser..."
    sleep 2
    open http://localhost:4173/ 2>/dev/null || xdg-open http://localhost:4173/ 2>/dev/null || echo "  Please open http://localhost:4173/ manually"
    echo ""
    echo "  Review the admin dashboard and press Enter when ready to deploy..."
    read
    
    # Stop preview server
    kill $PREVIEW_PID 2>/dev/null || true
else
    echo -e "${YELLOW}⚠${NC} Preview server test skipped"
    kill $PREVIEW_PID 2>/dev/null || true
fi

echo ""
echo -e "${BLUE}[5/5] Deploying to Netlify...${NC}"
echo ""

# Check if netlify-cli is installed
if ! command -v netlify &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Netlify CLI not found. Installing..."
    npm install -g netlify-cli
fi

echo "Deployment options:"
echo "  1. Deploy via Netlify CLI (manual)"
echo "  2. Deploy via GitHub (recommended)"
echo "  3. Deploy via drag & drop"
echo ""
read -p "Choose deployment method (1-3): " -n 1 -r
echo

case $REPLY in
    1)
        echo ""
        echo -e "${BLUE}→${NC} Deploying via Netlify CLI..."
        netlify login
        netlify deploy --prod --dir=dist
        ;;
    2)
        echo ""
        echo -e "${BLUE}→${NC} GitHub deployment setup"
        echo ""
        echo "Steps:"
        echo "  1. Push your code to GitHub (if not already done)"
        echo "  2. Go to: https://app.netlify.com/start"
        echo "  3. Click 'Import from Git' → Select your repo"
        echo "  4. Configure build settings:"
        echo "     - Base directory: web-admin"
        echo "     - Build command: npm run build"
        echo "     - Publish directory: web-admin/dist"
        echo "  5. Add environment variables from .env.production"
        echo "  6. Click 'Deploy site'"
        echo ""
        echo "Your code is ready for GitHub deployment!"
        echo ""
        read -p "Press Enter to open Netlify dashboard..."
        open "https://app.netlify.com/start" 2>/dev/null || xdg-open "https://app.netlify.com/start" 2>/dev/null || echo "Go to: https://app.netlify.com/start"
        ;;
    3)
        echo ""
        echo -e "${BLUE}→${NC} Drag & drop deployment"
        echo ""
        echo "Steps:"
        echo "  1. Go to: https://app.netlify.com/drop"
        echo "  2. Drag the 'dist' folder to the upload area"
        echo ""
        echo "Opening Netlify Drop..."
        open "https://app.netlify.com/drop" 2>/dev/null || xdg-open "https://app.netlify.com/drop" 2>/dev/null || echo "Go to: https://app.netlify.com/drop"
        echo ""
        echo "Dist folder location: $ADMIN_DIR/dist"
        ;;
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                  ✅ Deployment Ready! 🎉                 ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Once deployed, copy your Netlify URL"
echo "  2. Update backend CORS settings (Render.com):"
echo "     ALLOWED_ORIGINS=<frontend-url>,<admin-url>"
echo "  3. Test login with admin credentials"
echo "  4. Share the admin dashboard URL with your team"
echo ""
echo -e "${BLUE}Useful commands:${NC}"
echo "  Preview: npm run preview"
echo "  Build: npm run build"
echo "  Dev: npm run dev"
echo ""
