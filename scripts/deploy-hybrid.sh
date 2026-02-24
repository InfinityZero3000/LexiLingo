#!/bin/bash

###############################################################################
# Complete Hybrid Deployment Script
# Usage: bash scripts/deploy-hybrid.sh
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

clear
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║         🚀 LexiLingo Hybrid Deployment Setup 🚀          ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}║  Deploy Backend, Frontend, Admin to FREE cloud          ║${NC}"
echo -e "${CYAN}║  Keep AI Service running on your local machine          ║${NC}"
echo -e "${CYAN}║                                                          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}[1/7] Checking prerequisites...${NC}"
echo ""

# Check Git
if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ Git not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Git installed"

# Check Flutter
if ! command -v flutter &> /dev/null; then
    echo -e "${YELLOW}✗ Flutter not found (needed for web deployment)${NC}"
    echo "  Install: https://flutter.dev/docs/get-started/install"
else
    echo -e "${GREEN}✓${NC} Flutter installed ($(flutter --version | head -1))"
fi

# Check Node.js
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗ Node.js not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Node.js installed ($(node --version))"

# Check Python
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}✗ Python3 not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Python3 installed ($(python3 --version))"

echo ""
sleep 1

# Setup local AI service
echo -e "${BLUE}[2/7] Starting local AI Service...${NC}"
echo ""
read -p "Start AI service locally? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    bash "$PROJECT_ROOT/scripts/start-ai-local.sh"
    echo ""
    echo -e "${GREEN}✓${NC} AI Service started"
    
    # Get tunnel URL
    if [ -f "$PROJECT_ROOT/logs/tunnel-url.txt" ]; then
        TUNNEL_URL=$(cat "$PROJECT_ROOT/logs/tunnel-url.txt")
        echo -e "${YELLOW}📝 Tunnel URL:${NC} $TUNNEL_URL"
        echo ""
    else
        echo -e "${RED}✗${NC} Could not find tunnel URL"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC} Skipped AI service setup"
    echo "Enter your AI service URL (or leave empty to configure later):"
    read TUNNEL_URL
fi

sleep 2

# Database setup
echo -e "${BLUE}[3/7] Database Setup (Supabase)${NC}"
echo ""
echo "📋 Steps:"
echo "  1. Go to: https://supabase.com/dashboard"
echo "  2. Create new project: 'lexilingo'"
echo "  3. Copy your connection string"
echo ""
read -p "Enter Supabase connection string (postgresql://...): " DATABASE_URL
echo ""
echo -e "${GREEN}✓${NC} Database URL saved"

sleep 1

# Backend deployment
echo -e "${BLUE}[4/7] Backend Deployment (Render.com)${NC}"
echo ""
echo "📋 Steps:"
echo "  1. Go to: https://render.com/dashboard"
echo "  2. Click 'New +' → 'Blueprint'"
echo "  3. Connect your GitHub repo: InfinityZero3000/LexiLingo"
echo "  4. Render will read backend-service/render.yaml"
echo "  5. Set environment variables:"
echo "     - DATABASE_URL: $DATABASE_URL"
echo "     - AI_SERVICE_URL: $TUNNEL_URL"
echo "     - FIREBASE_SERVICE_ACCOUNT: (paste JSON content)"
echo ""
echo "  6. Deploy!"
echo ""
read -p "Press Enter when backend is deployed..."
echo ""
read -p "Enter your backend URL (https://xxx.onrender.com): " BACKEND_URL
echo -e "${GREEN}✓${NC} Backend URL saved"

sleep 1

# Frontend deployment
echo -e "${BLUE}[5/7] Flutter Web Deployment (Vercel)${NC}"
echo ""

if command -v flutter &> /dev/null; then
    echo -e "${BLUE}→${NC} Building Flutter web..."
    cd "$PROJECT_ROOT/flutter-app"
    flutter build web --release
    echo -e "${GREEN}✓${NC} Flutter web built"
    echo ""
fi

echo "📋 Steps:"
echo "  1. Go to: https://vercel.com/new"
echo "  2. Import GitHub repo: InfinityZero3000/LexiLingo"
echo "  3. Configure:"
echo "     - Framework Preset: Other"
echo "     - Root Directory: flutter-app"
echo "     - Build Command: flutter build web --release"
echo "     - Output Directory: build/web"
echo "  4. Environment Variables:"
echo "     - BACKEND_API_URL: $BACKEND_URL"
echo "     - AI_SERVICE_URL: $TUNNEL_URL"
echo "  5. Deploy!"
echo ""
read -p "Press Enter when frontend is deployed..."
echo ""
read -p "Enter your Vercel URL (https://xxx.vercel.app): " FRONTEND_URL
echo -e "${GREEN}✓${NC} Frontend URL saved"

sleep 1

# Web Admin deployment
echo -e "${BLUE}[6/7] Web Admin Deployment (Netlify)${NC}"
echo ""
echo "📋 Steps:"
echo "  1. Go to: https://app.netlify.com/start"
echo "  2. Import GitHub repo: InfinityZero3000/LexiLingo"
echo "  3. Configure:"
echo "     - Base directory: web-admin"
echo "     - Build command: npm run build"
echo "     - Publish directory: web-admin/dist"
echo "  4. Environment Variables:"
echo "     - VITE_BACKEND_URL: $BACKEND_URL"
echo "     - VITE_AI_SERVICE_URL: $TUNNEL_URL"
echo "  5. Deploy!"
echo ""
read -p "Press Enter when admin is deployed..."
echo ""
read -p "Enter your Netlify URL (https://xxx.netlify.app): " ADMIN_URL
echo -e "${GREEN}✓${NC} Admin URL saved"

sleep 1

# Update CORS settings
echo -e "${BLUE}[7/7] Final Configuration${NC}"
echo ""
echo "📋 Update CORS in Render.com backend:"
echo "  Environment Variables → ALLOWED_ORIGINS:"
echo "  $FRONTEND_URL,$ADMIN_URL"
echo ""
read -p "Press Enter when CORS is updated..."

# Generate summary
clear
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}║           ✅ Deployment Complete! 🎉                     ║${NC}"
echo -e "${GREEN}║                                                          ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📊 Deployment Summary:${NC}"
echo ""
echo -e "${BLUE}Frontend (Users):${NC}"
echo "  $FRONTEND_URL"
echo ""
echo -e "${BLUE}Admin Dashboard:${NC}"
echo "  $ADMIN_URL"
echo ""
echo -e "${BLUE}Backend API:${NC}"
echo "  $BACKEND_URL"
echo ""
echo -e "${BLUE}AI Service (Local):${NC}"
echo "  Public:  $TUNNEL_URL"
echo "  Private: http://localhost:8001"
echo ""
echo -e "${BLUE}Database:${NC}"
echo "  Supabase PostgreSQL"
echo ""
echo -e "${CYAN}💰 Monthly Cost: \$0 (+ ~\$6 electricity)${NC}"
echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "  1. Test all services"
echo "  2. Setup auto-start for AI service:"
echo "     bash scripts/setup-launchd.sh"
echo "  3. Monitor logs:"
echo "     tail -f logs/ai-local.log"
echo "  4. Setup uptime monitoring:"
echo "     https://uptimerobot.com (free)"
echo ""
echo -e "${BLUE}📚 Documentation:${NC}"
echo "  docs/HYBRID_DEPLOYMENT_GUIDE.md"
echo ""

# Save deployment info
cat > "$PROJECT_ROOT/deployment-info.txt" << EOF
# LexiLingo Hybrid Deployment Info
# Generated: $(date)

FRONTEND_URL=$FRONTEND_URL
ADMIN_URL=$ADMIN_URL
BACKEND_URL=$BACKEND_URL
AI_SERVICE_URL=$TUNNEL_URL
DATABASE_URL=$DATABASE_URL

# Useful commands:
# Start AI: bash scripts/start-ai-local.sh
# Stop AI:  bash scripts/stop-ai-local.sh
# Logs:     tail -f logs/ai-local.log
EOF

echo -e "${GREEN}✓${NC} Deployment info saved to deployment-info.txt"
echo ""
