#!/bin/bash
# LexiLingo - Start All Services (No Global .env)
# Uses Ollama + Qwen 3:8B for local LLM
# Created: 2026-02-03

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/logs"

# Create logs directory
mkdir -p "$LOG_DIR"

# Ports
BACKEND_PORT=8000
AI_PORT=8001
FLUTTER_PORT=8080
OLLAMA_PORT=11434

# PIDs for cleanup
BACKEND_PID=""
AI_PID=""
FLUTTER_PID=""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}🛑 Shutting down all services...${NC}"
    
    # Kill by PID if available
    [ -n "$FLUTTER_PID" ] && kill $FLUTTER_PID 2>/dev/null
    [ -n "$AI_PID" ] && kill $AI_PID 2>/dev/null
    [ -n "$BACKEND_PID" ] && kill $BACKEND_PID 2>/dev/null
    
    # Also kill by port to be safe
    lsof -ti:$BACKEND_PORT | xargs kill -9 2>/dev/null || true
    lsof -ti:$AI_PORT | xargs kill -9 2>/dev/null || true
    lsof -ti:$FLUTTER_PORT | xargs kill -9 2>/dev/null || true
    
    echo -e "${GREEN}✅ All services stopped${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Banner
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  LexiLingo - Ollama + Qwen3.0:8B       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check Ollama
echo -e "${YELLOW}🔍 Checking Ollama...${NC}"
if ! curl -s http://localhost:$OLLAMA_PORT/api/tags > /dev/null 2>&1; then
    echo -e "${RED}❌ Ollama is not running!${NC}"
    echo -e "   Start Ollama first: ${GREEN}ollama serve${NC}"
    exit 1
fi

# Check Qwen model
MODELS=$(curl -s http://localhost:$OLLAMA_PORT/api/tags | grep -o '"name":"[^"]*"' | head -5)
if echo "$MODELS" | grep -q "qwen3:8b"; then
    echo -e "   ${GREEN}✅ Found qwen3:8b model${NC}"
else
    echo -e "${YELLOW}⚠️  qwen3:8b not found. Available models:${NC}"
    echo "$MODELS"
    echo -e "${YELLOW}   Pulling qwen3:8b...${NC}"
    ollama pull qwen3:8b
fi

# Kill existing processes on ports
echo -e "${YELLOW}🧹 Cleaning up ports...${NC}"
for PORT in $BACKEND_PORT $AI_PORT $FLUTTER_PORT; do
    PID=$(lsof -ti:$PORT 2>/dev/null || true)
    if [ -n "$PID" ]; then
        echo -e "   Killing process on port $PORT..."
        kill -9 $PID 2>/dev/null || true
        sleep 1
    fi
done
echo -e "   ${GREEN}✅ Ports cleared${NC}"

# Export environment variables directly (no .env file)
export USE_OLLAMA=true
export OLLAMA_BASE_URL="http://localhost:11434"
export OLLAMA_MODEL="qwen3:8b"
export USE_GATEWAY=false
export USE_QWEN=false
export DEBUG=true
export LOG_LEVEL=INFO

# Backend service
echo -e "\n${YELLOW}🔧 Starting Backend Service (port $BACKEND_PORT)...${NC}"
cd "$PROJECT_ROOT/backend-service"

# Use explicit venv python path
BACKEND_PYTHON="$PROJECT_ROOT/backend-service/.venv/bin/python3"
if [ ! -f "$BACKEND_PYTHON" ]; then
    BACKEND_PYTHON="python3"
fi

$BACKEND_PYTHON -m uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT >> "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!
echo -e "   ${GREEN}✅ Backend started (PID: $BACKEND_PID)${NC}"

# Wait for backend
echo -n "   Waiting for backend..."
for i in {1..30}; do
    if curl -s http://localhost:$BACKEND_PORT/health > /dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# AI Service
echo -e "${YELLOW}🤖 Starting AI Service (port $AI_PORT)...${NC}"
cd "$PROJECT_ROOT/ai-service"

# Use explicit venv python path
AI_PYTHON="$PROJECT_ROOT/ai-service/.venv/bin/python3"
if [ ! -f "$AI_PYTHON" ]; then
    AI_PYTHON="python3"
fi

$AI_PYTHON -m uvicorn api.main_lite:app --host 0.0.0.0 --port $AI_PORT >> "$LOG_DIR/ai-service.log" 2>&1 &
AI_PID=$!
echo -e "   ${GREEN}✅ AI Service started (PID: $AI_PID)${NC}"

# Wait for AI service
echo -n "   Waiting for AI service..."
for i in {1..60}; do
    if curl -s http://localhost:$AI_PORT/health > /dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e " ${YELLOW}Timeout - check logs${NC}"
    fi
    echo -n "."
    sleep 1
done

# Flutter Web
echo -e "${YELLOW}📱 Starting Flutter Web (port $FLUTTER_PORT)...${NC}"
cd "$PROJECT_ROOT/flutter-app"

# Don't read flutter-app/.env - use environment variables instead
unset $(grep -v '^#' .env 2>/dev/null | sed -E 's/(.*)=.*/\1/' | xargs) 2>/dev/null || true

# Flutter run without .env
flutter run -d chrome --web-port=$FLUTTER_PORT >> "$LOG_DIR/flutter.log" 2>&1 &
FLUTTER_PID=$!

# Status banner
echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    All Services Started!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📍 URLs:${NC}"
echo -e "  Backend:    ${GREEN}http://localhost:$BACKEND_PORT${NC}"
echo -e "  API Docs:   ${GREEN}http://localhost:$BACKEND_PORT/docs${NC}"
echo -e "  AI Service: ${GREEN}http://localhost:$AI_PORT${NC}"
echo -e "  AI Docs:    ${GREEN}http://localhost:$AI_PORT/docs${NC}"
echo -e "  Flutter:    ${GREEN}http://localhost:$FLUTTER_PORT${NC} (building...)"
echo -e "  Ollama:     ${GREEN}http://localhost:$OLLAMA_PORT${NC}"
echo ""
echo -e "${BLUE}🦙 Ollama Status:${NC}"
echo -e "  Model: ${GREEN}qwen3:8b${NC} (8.2B params, Q4_K_M)"
echo ""
echo -e "${BLUE}📋 Logs:${NC}"
echo -e "  Backend:  tail -f $LOG_DIR/backend.log"
echo -e "  AI:       tail -f $LOG_DIR/ai-service.log"
echo -e "  Flutter:  tail -f $LOG_DIR/flutter.log"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Wait for processes
wait
