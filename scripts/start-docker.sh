#!/bin/bash
# ===========================================
# LexiLingo - Start All Services with Docker
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  LexiLingo - Docker Services Startup   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

cd "$PROJECT_ROOT"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Check for .env file and create if missing
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}Creating .env file...${NC}"
    cat > .env << 'EOF'
SECRET_KEY=your-secret-key-change-in-production
DEBUG=True
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
GEMINI_API_KEY=your-gemini-api-key
EOF
fi

# Stop existing containers
echo -e "${YELLOW}🧹 Stopping existing containers...${NC}"
docker-compose down 2>/dev/null || true

# Build and start services
echo -e "${BLUE}🚀 Building and starting Docker services...${NC}"
echo ""

# Start only databases first
echo -e "${BLUE}📦 Starting databases (postgres, mongodb, redis)...${NC}"
docker-compose up -d postgres mongodb redis

# Wait for databases to be healthy
echo -e "${BLUE}⏳ Waiting for databases to be ready...${NC}"
for i in {1..60}; do
    postgres_ok=$(docker-compose ps postgres | grep -c "healthy" 2>/dev/null || echo "0")
    mongodb_ok=$(docker-compose ps mongodb | grep -c "healthy" 2>/dev/null || echo "0")
    redis_ok=$(docker-compose ps redis | grep -c "healthy" 2>/dev/null || echo "0")
    
    if [ "$postgres_ok" -ge 1 ] && [ "$mongodb_ok" -ge 1 ] && [ "$redis_ok" -ge 1 ]; then
        echo -e "${GREEN}✅ All databases are ready!${NC}"
        break
    fi
    
    if [ $i -eq 60 ]; then
        echo -e "${YELLOW}⚠ Some databases may not be ready, continuing anyway...${NC}"
    fi
    echo -n "."
    sleep 2
done
echo ""

# Start backend and AI services
echo -e "${BLUE}🔧 Starting backend-service and ai-service...${NC}"
docker-compose up -d backend-service ai-service

# Wait for services
echo -e "${BLUE}⏳ Waiting for API services...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Backend service is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

for i in {1..30}; do
    if curl -s http://localhost:8001/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ AI service is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Show status
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Docker Services Started! 🐳         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
docker-compose ps
echo ""
echo -e "${BLUE}📍 URLs:${NC}"
echo -e "  Backend API:  ${YELLOW}http://localhost:8000${NC}"
echo -e "  API Docs:     ${YELLOW}http://localhost:8000/docs${NC}"
echo -e "  AI Service:   ${YELLOW}http://localhost:8001${NC}"
echo -e "  AI Docs:      ${YELLOW}http://localhost:8001/docs${NC}"
echo ""
echo -e "${BLUE}📋 Commands:${NC}"
echo -e "  View logs:    ${YELLOW}docker-compose logs -f${NC}"
echo -e "  Stop all:     ${YELLOW}docker-compose down${NC}"
echo -e "  Restart:      ${YELLOW}docker-compose restart${NC}"
echo ""
echo -e "${YELLOW}Note: Run Flutter separately with: cd flutter-app && flutter run -d chrome --web-port=8080${NC}"
