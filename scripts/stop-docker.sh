#!/bin/bash
# ===========================================
# LexiLingo - Stop All Docker Services
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  LexiLingo - Stopping Docker Services  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

cd "$PROJECT_ROOT"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running${NC}"
    exit 1
fi

# Show current running containers
echo -e "${BLUE}📊 Current containers:${NC}"
docker-compose ps
echo ""

# Ask for confirmation
read -p "$(echo -e ${YELLOW}Stop all services? [y/N]:${NC} )" -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cancelled${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}🛑 Stopping all services...${NC}"

# Stop services in order
echo -e "${BLUE}Stopping application services...${NC}"
docker-compose stop ai-service backend-service

echo -e "${BLUE}Stopping databases...${NC}"
docker-compose stop postgres mongodb redis

# Remove containers
echo -e "${YELLOW}Removing containers...${NC}"
docker-compose down

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    All Services Stopped! ✅            ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Show final status
CONTAINERS=$(docker-compose ps -q | wc -l | tr -d ' ')
if [ "$CONTAINERS" -eq 0 ]; then
    echo -e "${GREEN}✅ All containers stopped successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Some containers may still be running:${NC}"
    docker-compose ps
fi

echo ""
echo -e "${BLUE}💡 Tips:${NC}"
echo -e "  ${CYAN}Start services:${NC}       ${YELLOW}bash scripts/start-docker.sh${NC}"
echo -e "  ${CYAN}Remove volumes:${NC}       ${YELLOW}docker-compose down -v${NC}"
echo -e "  ${CYAN}Remove all data:${NC}      ${YELLOW}docker-compose down -v --remove-orphans${NC}"
