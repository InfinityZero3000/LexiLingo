#!/bin/bash
# ===========================================
# LexiLingo - Start All Services with Docker
# Enhanced version with unified monitoring
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
mkdir -p "$LOG_DIR"

# Load environment variables from .env if exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  LexiLingo - Docker Services Startup   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

cd "$PROJECT_ROOT"

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Shutting down all Docker services...${NC}"
    docker-compose down
    echo -e "${GREEN}✅ All services stopped${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Function to check Docker installation
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker is not installed${NC}"
        echo -e "${YELLOW}Please install Docker from: https://docs.docker.com/get-docker/${NC}"
        exit 1
    fi
    
    if ! docker info > /dev/null 2>&1; then
        echo -e "${RED}❌ Docker daemon is not running${NC}"
        echo -e "${YELLOW}Please start Docker Desktop or Docker daemon${NC}"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}❌ docker-compose is not installed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Docker is ready${NC}"
}

# Function to validate environment
validate_env() {
    echo -e "${YELLOW}🔍 Validating environment...${NC}"
    
    if [ ! -f ".env" ]; then
        echo -e "${YELLOW}⚠️  .env file not found, creating default...${NC}"
        cat > .env << 'EOF'
SECRET_KEY=your-secret-key-change-in-production
DEBUG=True
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080
GEMINI_API_KEY=your-gemini-api-key
EOF
        echo -e "${RED}❌ Please update .env file with your actual configuration${NC}"
        echo -e "${YELLOW}Especially set GEMINI_API_KEY before continuing${NC}"
        exit 1
    fi
    
    # Check GEMINI_API_KEY
    if [ -z "$GEMINI_API_KEY" ] || [ "$GEMINI_API_KEY" = "your-gemini-api-key" ]; then
        echo -e "${RED}❌ GEMINI_API_KEY is not set or is default value${NC}"
        echo -e "${YELLOW}Please set it in .env file${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Environment validated${NC}"
}

# Function to check port availability
check_ports() {
    echo -e "${YELLOW}🔍 Checking port availability...${NC}"
    PORTS_OK=true
    
    for port_info in "5432:PostgreSQL" "27017:MongoDB" "6379:Redis" "8000:Backend" "8001:AI Service"; do
        port=${port_info%%:*}
        service=${port_info#*:}
        
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            process=$(lsof -Pi :$port -sTCP:LISTEN -t)
            cmd=$(ps -p $process -o comm= 2>/dev/null)
            echo -e "   ${YELLOW}⚠️  Port $port ($service) is occupied by PID $process ($cmd)${NC}"
            PORTS_OK=false
        fi
    done
    
    if [ "$PORTS_OK" = false ]; then
        echo -e "${YELLOW}🧹 Cleaning up occupied ports...${NC}"
        docker-compose down 2>/dev/null || true
        sleep 2
        echo -e "${GREEN}✅ Ports cleaned${NC}"
    else
        echo -e "${GREEN}✅ All ports available${NC}"
    fi
}

# Function to check container health
check_container_health() {
    local container=$1
    local max_wait=${2:-60}
    
    for i in $(seq 1 $max_wait); do
        health=$(docker inspect --format='{{.State.Health.Status}}' $container 2>/dev/null || echo "none")
        
        if [ "$health" = "healthy" ]; then
            return 0
        elif [ "$health" = "none" ]; then
            # Container doesn't have health check, check if running
            status=$(docker inspect --format='{{.State.Status}}' $container 2>/dev/null || echo "none")
            if [ "$status" = "running" ]; then
                return 0
            fi
        fi
        
        if [ $i -eq $max_wait ]; then
            return 1
        fi
        
        echo -n "."
        sleep 2
    done
    
    return 1
}

# Function to check service endpoint
check_endpoint() {
    local url=$1
    local max_wait=${2:-30}
    
    for i in $(seq 1 $max_wait); do
        if curl -sf "$url" > /dev/null 2>&1; then
            return 0
        fi
        
        if [ $i -eq $max_wait ]; then
            return 1
        fi
        
        echo -n "."
        sleep 2
    done
    
    return 1
}

# Function to show container logs on error
show_logs() {
    local container=$1
    echo -e "\n${YELLOW}📋 Last 20 lines of $container logs:${NC}"
    docker logs --tail 20 $container 2>&1 | sed 's/^/   /'
}

# Start services
start_services() {
    echo -e "${BLUE}🚀 Building and starting Docker services...${NC}"
    echo ""
    
    # Stop existing containers
    echo -e "${YELLOW}🧹 Stopping existing containers...${NC}"
    docker-compose down 2>/dev/null || true
    
    # Pull latest images
    echo -e "${BLUE}📥 Pulling latest images...${NC}"
    docker-compose pull
    
    # Build custom images
    echo -e "${BLUE}🔨 Building custom images...${NC}"
    docker-compose build --no-cache
    
    echo ""
    
    # ============ Start Databases ============
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Step 1: Starting Databases${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "${BLUE}📦 Starting PostgreSQL...${NC}"
    docker-compose up -d postgres
    echo -n "   Waiting for PostgreSQL"
    if check_container_health "lexilingo-postgres" 60; then
        echo -e " ${GREEN}✅ Ready!${NC}"
    else
        echo -e " ${RED}❌ Failed!${NC}"
        show_logs "lexilingo-postgres"
        exit 1
    fi
    
    echo -e "${BLUE}📦 Starting MongoDB...${NC}"
    docker-compose up -d mongodb
    echo -n "   Waiting for MongoDB"
    if check_container_health "lexilingo-mongodb" 60; then
        echo -e " ${GREEN}✅ Ready!${NC}"
    else
        echo -e " ${RED}❌ Failed!${NC}"
        show_logs "lexilingo-mongodb"
        exit 1
    fi
    
    echo -e "${BLUE}📦 Starting Redis...${NC}"
    docker-compose up -d redis
    echo -n "   Waiting for Redis"
    if check_container_health "lexilingo-redis" 30; then
        echo -e " ${GREEN}✅ Ready!${NC}"
    else
        echo -e " ${RED}❌ Failed!${NC}"
        show_logs "lexilingo-redis"
        exit 1
    fi
    
    echo ""
    
    # ============ Start Application Services ============
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Step 2: Starting Application Services${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "${BLUE}🔧 Starting Backend Service...${NC}"
    docker-compose up -d backend-service
    echo -n "   Waiting for Backend (http://localhost:8000/health)"
    if check_endpoint "http://localhost:8000/health" 45; then
        echo -e " ${GREEN}✅ Ready!${NC}"
    else
        echo -e " ${RED}❌ Failed!${NC}"
        show_logs "lexilingo-backend-service"
        echo -e "${YELLOW}Check logs: docker-compose logs -f backend-service${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}🤖 Starting AI Service...${NC}"
    docker-compose up -d ai-service
    echo -n "   Waiting for AI Service (http://localhost:8001/health)"
    if check_endpoint "http://localhost:8001/health" 45; then
        echo -e " ${GREEN}✅ Ready!${NC}"
    else
        echo -e " ${RED}❌ Failed!${NC}"
        show_logs "lexilingo-ai-service"
        echo -e "${YELLOW}Check logs: docker-compose logs -f ai-service${NC}"
        exit 1
    fi
}

# Show final status
show_status() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    Docker Services Started! 🐳         ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # Show container status
    echo -e "${BLUE}📊 Container Status:${NC}"
    docker-compose ps
    
    echo ""
    echo -e "${BLUE}📍 Service URLs:${NC}"
    echo -e "  ${CYAN}Backend API:${NC}   ${YELLOW}http://localhost:8000${NC}"
    echo -e "  ${CYAN}API Docs:${NC}      ${YELLOW}http://localhost:8000/docs${NC}"
    echo -e "  ${CYAN}AI Service:${NC}    ${YELLOW}http://localhost:8001${NC}"
    echo -e "  ${CYAN}AI Docs:${NC}       ${YELLOW}http://localhost:8001/docs${NC}"
    
    echo ""
    echo -e "${BLUE}💾 Database Connections:${NC}"
    echo -e "  ${CYAN}PostgreSQL:${NC}    ${YELLOW}localhost:5432${NC} (user: lexilingo, db: lexilingo)"
    echo -e "  ${CYAN}MongoDB:${NC}       ${YELLOW}localhost:27017${NC} (db: lexilingo)"
    echo -e "  ${CYAN}Redis:${NC}         ${YELLOW}localhost:6379${NC}"
    
    echo ""
    echo -e "${BLUE}📋 Useful Commands:${NC}"
    echo -e "  ${CYAN}View all logs:${NC}      ${YELLOW}docker-compose logs -f${NC}"
    echo -e "  ${CYAN}View backend logs:${NC}  ${YELLOW}docker-compose logs -f backend-service${NC}"
    echo -e "  ${CYAN}View AI logs:${NC}       ${YELLOW}docker-compose logs -f ai-service${NC}"
    echo -e "  ${CYAN}Stop all services:${NC}  ${YELLOW}docker-compose down${NC}"
    echo -e "  ${CYAN}Restart service:${NC}    ${YELLOW}docker-compose restart <service-name>${NC}"
    echo -e "  ${CYAN}View status:${NC}        ${YELLOW}docker-compose ps${NC}"
    
    echo ""
    echo -e "${MAGENTA}📱 Frontend:${NC}"
    echo -e "  ${YELLOW}cd flutter-app && flutter run -d chrome --web-port=8080${NC}"
    
    echo ""
    echo -e "${GREEN}✨ All services are running. Press Ctrl+C to stop all services.${NC}"
    echo ""
}

# Main execution
main() {
    check_docker
    validate_env
    check_ports
    start_services
    show_status
    
    # Keep script running and follow logs
    echo -e "${BLUE}📋 Following service logs (press Ctrl+C to stop):${NC}"
    echo ""
    docker-compose logs -f
}

main
