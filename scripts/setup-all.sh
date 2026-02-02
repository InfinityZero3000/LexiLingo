#!/bin/bash

# ================================================
# LexiLingo - Setup All Services
# ================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   LexiLingo - Setup All Services      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# ================================================
# Check Prerequisites
# ================================================
echo -e "${YELLOW}📋 Checking prerequisites...${NC}"

command -v python3 >/dev/null 2>&1 || { echo -e "${RED}Python 3 is required${NC}"; exit 1; }
command -v flutter >/dev/null 2>&1 || { echo -e "${RED}Flutter is required${NC}"; exit 1; }
command -v psql >/dev/null 2>&1 || { echo -e "${RED}❌ PostgreSQL is required${NC}"; exit 1; }

echo -e "${GREEN}✅ All prerequisites met${NC}"
echo ""

# ================================================
# Setup Backend Service
# ================================================
echo -e "${BLUE}🔧 Setting up Backend Service...${NC}"
cd "$PROJECT_ROOT/backend-service"

# Create virtual environment
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies
echo "Installing Python dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

# Check .env file
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠️  Creating .env from .env.example${NC}"
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Please edit backend-service/.env with your database credentials${NC}"
fi

echo -e "${GREEN}✅ Backend service setup complete${NC}"
echo ""

# ================================================
# Setup Database
# ================================================
echo -e "${BLUE}🗄️  Setting up Database...${NC}"

# Check if database exists
if psql -lqt | cut -d \| -f 1 | grep -qw lexilingo; then
    echo -e "${GREEN}✅ Database 'lexilingo' already exists${NC}"
else
    echo "Creating database 'lexilingo'..."
    createdb lexilingo || echo -e "${YELLOW}⚠️  Could not create database (may already exist)${NC}"
fi

# Run migrations
echo "Running database migrations..."
alembic upgrade head || echo -e "${YELLOW}⚠️  Migrations may not be set up yet${NC}"

echo -e "${GREEN}✅ Database setup complete${NC}"
echo ""

# ================================================
# Setup AI Service
# ================================================
echo -e "${BLUE}🤖 Setting up AI Service...${NC}"
cd "$PROJECT_ROOT/ai-service"

# Create virtual environment
if [ ! -d "venv" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Install dependencies
echo "Installing AI service dependencies..."
pip install -q --upgrade pip
pip install -q -r requirements.txt

# Check .env file
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠️  Creating .env from .env.example${NC}"
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Please edit ai-service/.env with your API keys${NC}"
fi

echo -e "${GREEN}✅ AI service setup complete${NC}"
echo ""

# ================================================
# Setup Flutter App
# ================================================
echo -e "${BLUE}📱 Setting up Flutter App...${NC}"
cd "$PROJECT_ROOT/flutter-app"

# Get Flutter dependencies
echo "Getting Flutter dependencies..."
flutter pub get

# Check .env file
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}⚠️  Creating .env from .env.example${NC}"
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Please edit flutter-app/.env with your configuration${NC}"
fi

echo -e "${GREEN}✅ Flutter app setup complete${NC}"
echo ""

# ================================================
# Summary
# ================================================
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Setup Complete! 🎉                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Edit configuration files (.env) in each service"
echo "2. Run: ${YELLOW}./scripts/start-all.sh${NC} to start all services"
echo ""
echo -e "${BLUE}Service locations:${NC}"
echo "  • Backend:  http://localhost:8000"
echo "  • Backend Docs: http://localhost:8000/docs"
echo "  • AI Service: http://localhost:8001"
echo "  • Flutter Web: http://localhost:8080"
echo ""
