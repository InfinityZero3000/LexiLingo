#!/bin/bash
# ===========================================
# LexiLingo - Start All Services with iOS
# Runs Backend, AI, and Flutter iOS Simulator
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PID_DIR="$PROJECT_ROOT/.pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

# Load environment variables from .env if exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    echo -e "${GREEN}✅ Loaded environment from .env${NC}"
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   LexiLingo - Starting with iOS 📱     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Shutting down all services...${NC}"
    
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
    
    # Kill processes on ports
    lsof -ti :8000 | xargs kill -9 2>/dev/null || true
    lsof -ti :8001 | xargs kill -9 2>/dev/null || true
    
    echo -e "${GREEN}✅ All services stopped${NC}"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Function to check and report port status
check_port() {
    local port=$1
    local service=$2
    local process=$(lsof -ti :$port 2>/dev/null)
    
    if [ -n "$process" ]; then
        local cmd=$(ps -p $process -o comm= 2>/dev/null)
        echo -e "   ${YELLOW}⚠️  Port $port is occupied by PID $process ($cmd)${NC}"
        return 1
    fi
    return 0
}

# Function to kill process on port
kill_port() {
    local port=$1
    local service=$2
    if lsof -ti :$port >/dev/null 2>&1; then
        echo -e "   ${YELLOW}Killing process on port $port for $service...${NC}"
        lsof -ti :$port | xargs kill -9 2>/dev/null || true
        sleep 1
        if lsof -ti :$port >/dev/null 2>&1; then
            echo -e "   ${RED}❌ Failed to kill process on port $port${NC}"
            return 1
        fi
        echo -e "   ${GREEN}✅ Port $port freed${NC}"
    fi
    return 0
}

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

# Check all required ports
echo ""
echo -e "${YELLOW}🔍 Checking port availability...${NC}"
PORTS_OK=true

for port_info in "8000:Backend" "8001:AI Service"; do
    port=${port_info%%:*}
    service=${port_info#*:}
    if ! check_port $port "$service"; then
        PORTS_OK=false
    fi
done

if [ "$PORTS_OK" = false ]; then
    echo ""
    echo -e "${YELLOW}🧹 Cleaning up occupied ports...${NC}"
    kill_port 8000 "Backend"
    kill_port 8001 "AI Service"
    echo ""
else
    echo -e "${GREEN}✅ All ports available${NC}"
    echo ""
fi

# Clean up old PID files
rm -f "$PID_DIR"/*.pid

# ============ Backend Service ============
echo -e "${BLUE}🔧 Starting Backend Service (port 8000)...${NC}"

BACKEND_VENV="$PROJECT_ROOT/backend-service/.venv"

# Clear old logs
> "$LOG_DIR/backend.log"

# Check if venv exists
if [ ! -d "$BACKEND_VENV" ]; then
    echo -e "   ${RED}❌ Virtual environment not found at $BACKEND_VENV${NC}"
    echo -e "   ${YELLOW}Run: cd backend-service && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt${NC}"
    exit 1
fi

# Start backend
(
    cd "$PROJECT_ROOT/backend-service"
    source .venv/bin/activate
    echo "$(date): Starting Backend on port 8000" >> "$LOG_DIR/backend.log"
    python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 >> "$LOG_DIR/backend.log" 2>&1
) &
BACKEND_PID=$!
echo $BACKEND_PID > "$PID_DIR/backend.pid"
echo -e "${GREEN}✅ Backend started (PID: $BACKEND_PID)${NC}"

# Wait for backend
echo -n "   Waiting for backend"
for i in {1..60}; do
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    
    # Check if process still running
    if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo -e " ${RED}Failed!${NC}"
        echo -e "   ${RED}❌ Backend process died. Check logs:${NC}"
        echo -e "   ${YELLOW}tail -30 $LOG_DIR/backend.log${NC}"
        tail -20 "$LOG_DIR/backend.log"
        cleanup
    fi
    
    if [ $i -eq 60 ]; then
        echo -e " ${RED}Timeout!${NC}"
        echo -e "   ${YELLOW}Check logs: tail -f $LOG_DIR/backend.log${NC}"
        tail -20 "$LOG_DIR/backend.log"
        cleanup
    fi
    echo -n "."
    sleep 1
done

# ============ AI Service ============
echo -e "${BLUE}🤖 Starting AI Service (port 8001)...${NC}"

AI_VENV="$PROJECT_ROOT/.venv"

# Check if venv exists
if [ ! -d "$AI_VENV" ]; then
    echo -e "   ${RED}❌ Virtual environment not found at $AI_VENV${NC}"
    echo -e "   ${YELLOW}Run: python3 -m venv .venv && source .venv/bin/activate && pip install -r ai-service/requirements.txt${NC}"
    exit 1
fi

# Check if Gemini API key is set
if [ -z "$GEMINI_API_KEY" ]; then
    echo -e "   ${RED}❌ GEMINI_API_KEY environment variable not set${NC}"
    echo -e "   ${YELLOW}Please set it before running:${NC}"
    echo -e "   ${YELLOW}export GEMINI_API_KEY='your-api-key-here'${NC}"
    echo -e "   ${YELLOW}or add it to your ~/.bashrc or ~/.zshrc${NC}"
    exit 1
fi

# Clear old logs
> "$LOG_DIR/ai-service.log"

# Start AI service
(
    cd "$PROJECT_ROOT/ai-service"
    source "$AI_VENV/bin/activate"
    export GEMINI_API_KEY="$GEMINI_API_KEY"
    echo "$(date): Starting AI Service on port 8001" >> "$LOG_DIR/ai-service.log"
    python3 -m uvicorn api.main_lite:app --host 0.0.0.0 --port 8001 >> "$LOG_DIR/ai-service.log" 2>&1
) &
AI_PID=$!
echo $AI_PID > "$PID_DIR/ai-service.pid"
echo -e "${GREEN}✅ AI Service started (PID: $AI_PID)${NC}"

# Wait for AI
echo -n "   Waiting for AI service"
for i in {1..30}; do
    if lsof -Pi :8001 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi
    
    # Check if process still running
    if ! kill -0 "$AI_PID" 2>/dev/null; then
        echo -e " ${RED}Failed!${NC}"
        echo -e "   ${RED}❌ AI Service process died. Check logs:${NC}"
        echo -e "   ${YELLOW}tail -30 $LOG_DIR/ai-service.log${NC}"
        tail -20 "$LOG_DIR/ai-service.log"
        cleanup
    fi
    
    if [ $i -eq 30 ]; then
        echo -e " ${RED}Timeout!${NC}"
        echo -e "   ${YELLOW}Check logs: tail -f $LOG_DIR/ai-service.log${NC}"
        tail -20 "$LOG_DIR/ai-service.log"
        cleanup
    fi
    echo -n "."
    sleep 1
done

# ============ Flutter iOS ============
echo ""
echo -e "${BLUE}📱 Starting Flutter iOS App...${NC}"
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
echo -e "  Backend:    ${YELLOW}http://localhost:8000${NC}"
echo -e "  API Docs:   ${YELLOW}http://localhost:8000/docs${NC}"
echo -e "  AI Service: ${YELLOW}http://localhost:8001${NC}"
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
