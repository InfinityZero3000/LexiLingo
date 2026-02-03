#!/bin/bash
# LexiLingo - Start All Services with iOS Simulator
# Uses Ollama + Qwen 3:8B for local LLM
# Created: 2026-02-03

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LOG_DIR="$PROJECT_ROOT/logs"
PID_DIR="$PROJECT_ROOT/.pids"

# Create directories
mkdir -p "$LOG_DIR" "$PID_DIR"

# Ports
BACKEND_PORT=8000
AI_PORT=8001
OLLAMA_PORT=11434

# PIDs for cleanup
BACKEND_PID=""
AI_PID=""

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}🛑 Shutting down all services...${NC}"
    
    # Kill by PID files
    for pidfile in "$PID_DIR"/*.pid; do
        if [ -f "$pidfile" ]; then
            pid=$(cat "$pidfile")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null
            fi
            rm -f "$pidfile"
        fi
    done
    
    # Also kill by port to be safe
    lsof -ti:$BACKEND_PORT | xargs kill -9 2>/dev/null || true
    lsof -ti:$AI_PORT | xargs kill -9 2>/dev/null || true
    
    echo -e "${GREEN}✅ All services stopped${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Banner
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  LexiLingo - Ollama + iOS Simulator    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Function to get iOS simulator device ID
get_ios_simulator() {
    # Get the first booted simulator or a good default
    local booted=$(xcrun simctl list devices | grep "Booted" | head -1 | grep -o '([A-F0-9-]\{36\})' | tr -d '()')
    if [ -n "$booted" ]; then
        echo "$booted"
        return 0
    fi
    
    # If none booted, look for iPhone 15 Pro or similar
    local device_id=$(xcrun simctl list devices available | grep -E "iPhone 1[5-9]|iPhone 2" | head -1 | grep -o '([A-F0-9-]\{36\})' | tr -d '()')
    if [ -n "$device_id" ]; then
        echo "$device_id"
        return 0
    fi
    
    # Fallback to any available iPhone
    local fallback=$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -o '([A-F0-9-]\{36\})' | tr -d '()')
    echo "$fallback"
}

# Check iOS simulator availability
echo -e "${YELLOW}🔍 Checking iOS Simulator...${NC}"
SIMULATOR_ID=$(get_ios_simulator)

if [ -z "$SIMULATOR_ID" ]; then
    echo -e "   ${RED}❌ No iOS simulator found${NC}"
    echo -e "   ${YELLOW}Please install Xcode and create a simulator${NC}"
    echo -e "   ${YELLOW}Or run: open -a Simulator${NC}"
    exit 1
fi

SIMULATOR_NAME=$(xcrun simctl list devices | grep "$SIMULATOR_ID" | sed 's/(.*//' | xargs)
echo -e "   ${GREEN}✅ Found simulator: $SIMULATOR_NAME${NC}"

# Boot simulator if not already booted
BOOTED=$(xcrun simctl list devices | grep "$SIMULATOR_ID" | grep "Booted")
if [ -z "$BOOTED" ]; then
    echo -e "   ${YELLOW}⏳ Booting simulator...${NC}"
    xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
    sleep 2
fi

# Open Simulator app
echo -e "   ${CYAN}📱 Opening Simulator app...${NC}"
open -a Simulator

# Check Ollama
echo -e "\n${YELLOW}🔍 Checking Ollama...${NC}"
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
echo -e "\n${YELLOW}🧹 Cleaning up ports...${NC}"
for PORT in $BACKEND_PORT $AI_PORT; do
    PID=$(lsof -ti:$PORT 2>/dev/null || true)
    if [ -n "$PID" ]; then
        echo -e "   Killing process on port $PORT..."
        kill -9 $PID 2>/dev/null || true
        sleep 1
    fi
done
echo -e "   ${GREEN}✅ Ports cleared${NC}"

# Clean up old PID files
rm -f "$PID_DIR"/*.pid

# Export environment variables for Ollama
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

# Clear old logs
> "$LOG_DIR/backend.log"

# Use explicit venv python path
BACKEND_PYTHON="$PROJECT_ROOT/backend-service/.venv/bin/python3"
if [ ! -f "$BACKEND_PYTHON" ]; then
    echo -e "   ${RED}❌ Backend venv not found at $BACKEND_PYTHON${NC}"
    echo -e "   ${YELLOW}Run: cd backend-service && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt${NC}"
    exit 1
fi

$BACKEND_PYTHON -m uvicorn app.main:app --host 0.0.0.0 --port $BACKEND_PORT >> "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!
echo $BACKEND_PID > "$PID_DIR/backend.pid"
echo -e "   ${GREEN}✅ Backend started (PID: $BACKEND_PID)${NC}"

# Wait for backend
echo -n "   Waiting for backend"
for i in {1..60}; do
    if lsof -Pi :$BACKEND_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    
    # Check if process still running
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo -e " ${RED}Failed!${NC}"
        echo -e "   ${RED}❌ Backend process died. Check logs:${NC}"
        tail -20 "$LOG_DIR/backend.log"
        cleanup
    fi
    
    if [ $i -eq 60 ]; then
        echo -e " ${RED}Timeout!${NC}"
        tail -20 "$LOG_DIR/backend.log"
        cleanup
    fi
    echo -n "."
    sleep 1
done

# AI Service
echo -e "\n${YELLOW}🤖 Starting AI Service (port $AI_PORT)...${NC}"
cd "$PROJECT_ROOT/ai-service"

# Clear old logs
> "$LOG_DIR/ai-service.log"

# Use explicit venv python path
AI_PYTHON="$PROJECT_ROOT/.venv/bin/python3"
if [ ! -f "$AI_PYTHON" ]; then
    echo -e "   ${RED}❌ AI venv not found at $AI_PYTHON${NC}"
    echo -e "   ${YELLOW}Run: python3 -m venv .venv && source .venv/bin/activate && pip install -r ai-service/requirements.txt${NC}"
    exit 1
fi

$AI_PYTHON -m uvicorn api.main_lite:app --host 0.0.0.0 --port $AI_PORT >> "$LOG_DIR/ai-service.log" 2>&1 &
AI_PID=$!
echo $AI_PID > "$PID_DIR/ai-service.pid"
echo -e "   ${GREEN}✅ AI Service started (PID: $AI_PID)${NC}"

# Wait for AI service
echo -n "   Waiting for AI service"
for i in {1..60}; do
    if lsof -Pi :$AI_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    
    # Check if process still running
    if ! kill -0 "$AI_PID" 2>/dev/null; then
        echo -e " ${RED}Failed!${NC}"
        echo -e "   ${RED}❌ AI Service process died. Check logs:${NC}"
        tail -20 "$LOG_DIR/ai-service.log"
        cleanup
    fi
    
    if [ $i -eq 60 ]; then
        echo -e " ${YELLOW}Timeout - check logs${NC}"
        tail -20 "$LOG_DIR/ai-service.log"
    fi
    echo -n "."
    sleep 1
done

# Flutter iOS
echo -e "\n${BLUE}📱 Starting Flutter iOS App...${NC}"
cd "$PROJECT_ROOT/flutter-app"

# Run pod install if needed
if [ ! -d "ios/Pods" ]; then
    echo -e "   ${YELLOW}⏳ Running pod install (first time setup)...${NC}"
    cd ios
    pod install --repo-update
    cd ..
fi

# Summary before Flutter starts
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    Backend Services Started! 🚀        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}📍 URLs:${NC}"
echo -e "  Backend:    ${YELLOW}http://localhost:$BACKEND_PORT${NC}"
echo -e "  API Docs:   ${YELLOW}http://localhost:$BACKEND_PORT/docs${NC}"
echo -e "  AI Service: ${YELLOW}http://localhost:$AI_PORT${NC}"
echo -e "  AI Docs:    ${YELLOW}http://localhost:$AI_PORT/docs${NC}"
echo -e "  Ollama:     ${YELLOW}http://localhost:$OLLAMA_PORT${NC}"
echo ""
echo -e "${BLUE}🦙 Ollama Status:${NC}"
echo -e "  Model:      ${GREEN}qwen3:8b${NC} (8.2B params, Q4_K_M)"
echo ""
echo -e "${BLUE}📱 iOS Simulator:${NC}"
echo -e "  Device:     ${CYAN}$SIMULATOR_NAME${NC}"
echo -e "  ID:         ${CYAN}$SIMULATOR_ID${NC}"
echo ""
echo -e "${BLUE}📋 Logs:${NC}"
echo -e "  Backend:    ${YELLOW}tail -f $LOG_DIR/backend.log${NC}"
echo -e "  AI:         ${YELLOW}tail -f $LOG_DIR/ai-service.log${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Start Flutter iOS in foreground (keeps script running)
flutter run -d "$SIMULATOR_ID"
