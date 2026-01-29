#!/bin/bash

# ================================================
# LexiLingo - Development Helper
# Quick commands for common development tasks
# ================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

show_help() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   LexiLingo - Development Helper      ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Usage: ./scripts/dev.sh [command]"
    echo ""
    echo "Commands:"
    echo "  setup       - Setup all services (first time)"
    echo "  start       - Start all services"
    echo "  stop        - Stop all services"
    echo "  restart     - Restart all services"
    echo "  status      - Check service status"
    echo "  logs        - View all logs (tail -f)"
    echo "  log-backend - View backend logs"
    echo "  log-ai      - View AI service logs"
    echo "  log-flutter - View Flutter logs"
    echo "  clean       - Clean logs and PIDs"
    echo "  db-reset    - Reset database"
    echo "  db-migrate  - Run database migrations"
    echo "  test-all    - Run all tests"
    echo "  lint        - Run linters"
    echo "  help        - Show this help"
    echo ""
}

case "$1" in
    setup)
        echo -e "${BLUE}Setting up all services...${NC}"
        "$PROJECT_ROOT/scripts/setup-all.sh"
        ;;
    start)
        echo -e "${BLUE}Starting all services...${NC}"
        "$PROJECT_ROOT/scripts/start-all.sh"
        ;;
    stop)
        echo -e "${BLUE}Stopping all services...${NC}"
        "$PROJECT_ROOT/scripts/stop-all.sh"
        ;;
    restart)
        echo -e "${BLUE}Restarting all services...${NC}"
        "$PROJECT_ROOT/scripts/stop-all.sh"
        sleep 2
        "$PROJECT_ROOT/scripts/start-all.sh"
        ;;
    status)
        "$PROJECT_ROOT/scripts/status.sh"
        ;;
    logs)
        echo -e "${BLUE}Viewing all logs (Ctrl+C to exit)...${NC}"
        tail -f "$PROJECT_ROOT/logs"/*.log
        ;;
    log-backend)
        echo -e "${BLUE}Viewing backend logs (Ctrl+C to exit)...${NC}"
        tail -f "$PROJECT_ROOT/logs/backend.log"
        ;;
    log-ai)
        echo -e "${BLUE}Viewing AI service logs (Ctrl+C to exit)...${NC}"
        tail -f "$PROJECT_ROOT/logs/ai-service.log"
        ;;
    log-flutter)
        echo -e "${BLUE}Viewing Flutter logs (Ctrl+C to exit)...${NC}"
        tail -f "$PROJECT_ROOT/logs/flutter-web.log"
        ;;
    clean)
        echo -e "${BLUE}Cleaning logs and PIDs...${NC}"
        rm -rf "$PROJECT_ROOT/logs"/*.log
        rm -rf "$PROJECT_ROOT/.pids"/*.pid
        echo -e "${GREEN}✅ Cleaned${NC}"
        ;;
    db-reset)
        echo -e "${YELLOW}⚠️  This will drop and recreate the database!${NC}"
        read -p "Are you sure? (yes/no): " confirm
        if [ "$confirm" = "yes" ]; then
            dropdb lexilingo 2>/dev/null || true
            createdb lexilingo
            cd "$PROJECT_ROOT/backend-service"
            source venv/bin/activate
            alembic upgrade head
            echo -e "${GREEN}✅ Database reset complete${NC}"
        else
            echo "Cancelled"
        fi
        ;;
    db-migrate)
        echo -e "${BLUE}Running database migrations...${NC}"
        cd "$PROJECT_ROOT/backend-service"
        source venv/bin/activate
        alembic upgrade head
        echo -e "${GREEN}✅ Migrations complete${NC}"
        ;;
    test-all)
        echo -e "${BLUE}Running all tests...${NC}"
        
        echo -e "\n${YELLOW}Backend tests:${NC}"
        cd "$PROJECT_ROOT/backend-service"
        source venv/bin/activate
        pytest tests/ -v
        
        echo -e "\n${YELLOW}Flutter tests:${NC}"
        cd "$PROJECT_ROOT/flutter-app"
        flutter test
        
        echo -e "${GREEN}✅ All tests complete${NC}"
        ;;
    lint)
        echo -e "${BLUE}Running linters...${NC}"
        
        echo -e "\n${YELLOW}Python linting (Backend):${NC}"
        cd "$PROJECT_ROOT/backend-service"
        source venv/bin/activate
        flake8 app/ || echo "Install flake8: pip install flake8"
        
        echo -e "\n${YELLOW}Python linting (AI Service):${NC}"
        cd "$PROJECT_ROOT/ai-service"
        source venv/bin/activate
        flake8 api/ || echo "Install flake8: pip install flake8"
        
        echo -e "\n${YELLOW}Flutter linting:${NC}"
        cd "$PROJECT_ROOT/flutter-app"
        flutter analyze
        
        echo -e "${GREEN}✅ Linting complete${NC}"
        ;;
    help|*)
        show_help
        ;;
esac
