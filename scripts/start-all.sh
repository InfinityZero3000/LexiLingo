#!/bin/bash
# LexiLingo - Start All Services (Simplified)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PID_DIR="$PROJECT_ROOT/.pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   LexiLingo - Starting All Services    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Kill existing processes on ports
echo -e "${YELLOW}🧹 Cleaning up old processes...${NC}"
lsof -ti :8000 | xargs kill -9 2>/dev/null || true
lsof -ti :8001 | xargs kill -9 2>/dev/null || true
lsof -ti :8080 | xargs kill -9 2>/dev/null || true
sleep 2

# Clean up old PID files
rm -f "$PID_DIR"/*.pid

# Backend Service
echo -e "${BLUE}🔧 Starting Backend Service...${NC}"
cd "$PROJECT_ROOT/backend-service"

# Try venv first, fallback to python3
if [ -f "$PROJECT_ROOT/backend-service/venv/bin/python" ]; then
    PYTHON_CMD="$PROJECT_ROOT/backend-service/venv/bin/python"
else
    PYTHON_CMD="python3"
fi

$PYTHON_CMD -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!
echo $BACKEND_PID > "$PID_DIR/backend.pid"
echo -e "${GREEN}✅ Backend started (PID: $BACKEND_PID)${NC}"

# Wait for backend
echo -n "   Waiting for backend..."
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

# AI Service (optional)
echo -e "${BLUE}🤖 Starting AI Service...${NC}"
cd "$PROJECT_ROOT/ai-service"

if [ -f "$PROJECT_ROOT/ai-service/venv/bin/python" ]; then
    AI_PYTHON_CMD="$PROJECT_ROOT/ai-service/venv/bin/python"
else
    AI_PYTHON_CMD="python3"
fi

$AI_PYTHON_CMD -m uvicorn api.main:app --host 0.0.0.0 --port 8001 > "$LOG_DIR/ai-service.log" 2>&1 &
AI_PID=$!
echo $AI_PID > "$PID_DIR/ai-service.pid"
echo -e "${GREEN}✅ AI Service started (PID: $AI_PID)${NC}"

# Wait for AI
echo -n "   Waiting for AI service..."
for i in {1..20}; do
    if curl -s http://localhost:8001/health > /dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

# Flutter Web
echo -e "${BLUE}📱 Starting Flutter Web...${NC}"
cd "$PROJECT_ROOT/flutter-app"

# Run Flutter directly instead of through script
flutter run -d chrome --web-port=8080 > "$LOG_DIR/flutter-web.log" 2>&1 &
FLUTTER_PID=$!
echo $FLUTTER_PID > "$PID_DIR/flutter-web.pid"
echo -e "${GREEN}✅ Flutter Web started (PID: $FLUTTER_PID)${NC}"

# Wait for Flutter
echo -n "   Waiting for Flutter (this may take a while)..."
for i in {1..60}; do
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    All Services Started! 🚀           ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📍 URLs:${NC}"
echo -e "  Backend:    ${YELLOW}http://localhost:8000${NC}"
echo -e "  API Docs:   ${YELLOW}http://localhost:8000/docs${NC}"
echo -e "  AI Service: ${YELLOW}http://localhost:8001${NC}"
echo -e "  Flutter:    ${YELLOW}http://localhost:8080${NC}"
echo ""
echo -e "${BLUE}📋 Logs:${NC}"
echo -e "  Backend:    ${YELLOW}$LOG_DIR/backend.log${NC}"
echo -e "  AI:         ${YELLOW}$LOG_DIR/ai-service.log${NC}"
echo -e "  Flutter:    ${YELLOW}$LOG_DIR/flutter-web.log${NC}"
echo ""
echo -e "${YELLOW}Stop all: bash scripts/stop-all.sh${NC}"
