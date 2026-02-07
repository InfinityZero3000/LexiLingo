#!/bin/bash
# ===========================================
# LexiLingo - Start All Services (Local)
# Runs Backend, AI, and Flutter without Docker
# ===========================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
PID_DIR="$PROJECT_ROOT/.pids"
mkdir -p "$LOG_DIR" "$PID_DIR"

# Load environment variables from .env if exists
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    echo -e "${GREEN}[OK] Loaded environment from .env${NC}"
fi

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                                       ║${NC}"
echo -e "${BLUE}║   ██╗     ███████╗██╗  ██╗██╗██╗     ██╗███╗   ██╗ ██████╗  ██████╗   ║${NC}"
echo -e "${BLUE}║   ██║     ██╔════╝╚██╗██╔╝██║██║     ██║████╗  ██║██╔════╝ ██╔═══██╗  ║${NC}"
echo -e "${BLUE}║   ██║     █████╗   ╚███╔╝ ██║██║     ██║██╔██╗ ██║██║  ███╗██║   ██║  ║${NC}"
echo -e "${BLUE}║   ██║     ██╔══╝   ██╔██╗ ██║██║     ██║██║╚██╗██║██║   ██║██║   ██║  ║${NC}"
echo -e "${BLUE}║   ███████╗███████╗██╔╝ ██╗██║███████╗██║██║ ╚████║╚██████╔╝╚██████╔╝  ║${NC}"
echo -e "${BLUE}║   ╚══════╝╚══════╝╚═╝  ╚═╝╚═╝╚══════╝╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝   ║${NC}"
echo -e "${BLUE}║                                                                       ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}[STOP] Shutting down all services...${NC}"
    
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
    lsof -ti :5176 | xargs kill -9 2>/dev/null || true
    lsof -ti :8080 | xargs kill -9 2>/dev/null || true
    
    echo -e "${GREEN}[OK] All services stopped${NC}"
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
        echo -e "   ${YELLOW}[WARN] Port $port is occupied by PID $process ($cmd)${NC}"
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
            echo -e "   ${RED}[ERROR] Failed to kill process on port $port${NC}"
            return 1
        fi
        echo -e "   ${GREEN}[OK] Port $port freed${NC}"
    fi
    return 0
}

# Always cleanup ports before starting
echo -e "${YELLOW}[CLEANUP] Stopping any existing services on ports...${NC}"
kill_port 8000 "Backend"
kill_port 8001 "AI Service"
kill_port 5176 "Admin Dashboard"
kill_port 8080 "Flutter"
echo -e "${GREEN}[OK] All ports cleared${NC}"
echo ""

# Clean up old PID files
rm -f "$PID_DIR"/*.pid

# ============ Backend Service ============
echo -e "${BLUE}[START] Starting Backend Service (port 8000)...${NC}"

BACKEND_VENV="$PROJECT_ROOT/backend-service/venv"

# Clear old logs
> "$LOG_DIR/backend.log"

# Check if venv exists
if [ ! -d "$BACKEND_VENV" ]; then
    echo -e "   ${RED}[ERROR] Virtual environment not found at $BACKEND_VENV${NC}"
    echo -e "   ${YELLOW}Run: cd backend-service && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt${NC}"
    exit 1
fi

# Start backend
(
    cd "$PROJECT_ROOT/backend-service"
    source venv/bin/activate
    echo "$(date): Starting Backend on port 8000" >> "$LOG_DIR/backend.log"
    python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 >> "$LOG_DIR/backend.log" 2>&1
) &
BACKEND_PID=$!
echo $BACKEND_PID > "$PID_DIR/backend.pid"
echo -e "${GREEN}[OK] Backend started (PID: $BACKEND_PID)${NC}"

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
        echo -e "   ${RED}[ERROR] Backend process died. Check logs:${NC}"
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
echo -e "${BLUE}[START] Starting AI Service (port 8001)...${NC}"

AI_VENV="$PROJECT_ROOT/.venv"

# Check if venv exists
if [ ! -d "$AI_VENV" ]; then
    echo -e "   ${RED}[ERROR] Virtual environment not found at $AI_VENV${NC}"
    echo -e "   ${YELLOW}Run: python3 -m venv .venv && source .venv/bin/activate && pip install -r ai-service/requirements.txt${NC}"
    exit 1
fi

# Check if Gemini API key is set (optional warning)
if [ -z "$GEMINI_API_KEY" ]; then
    echo -e "   ${YELLOW}[WARN] GEMINI_API_KEY not set - AI will use Qwen model only${NC}"
    echo -e "   [INFO] To enable Gemini: export GEMINI_API_KEY='your-key' in .env${NC}"
fi

# Clear old logs
> "$LOG_DIR/ai-service.log"

# Start AI service with main.py (full endpoints for Flutter)
(
    cd "$PROJECT_ROOT/ai-service"
    source "$AI_VENV/bin/activate"
    export PYTHONPATH="$PROJECT_ROOT/ai-service"
    export GEMINI_API_KEY="$GEMINI_API_KEY"
    export CHAT_MODEL="${CHAT_MODEL:-qwen}"
    export OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:1.5b}"
    export USE_GRAPHCAG="${USE_GRAPHCAG:-true}"
    echo "$(date): Starting AI Service on port 8001" >> "$LOG_DIR/ai-service.log"
    echo "$(date): CHAT_MODEL=$CHAT_MODEL, OLLAMA_MODEL=$OLLAMA_MODEL, USE_GRAPHCAG=$USE_GRAPHCAG" >> "$LOG_DIR/ai-service.log"
    python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 >> "$LOG_DIR/ai-service.log" 2>&1
) &
AI_PID=$!
echo $AI_PID > "$PID_DIR/ai-service.pid"
echo -e "${GREEN}[OK] AI Service started (PID: $AI_PID)${NC}"

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
        echo -e "   ${RED}[ERROR] AI Service process died. Check logs:${NC}"
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

# ============ Admin Dashboard ============
echo -e "${BLUE}[START] Starting Admin Dashboard (port 5176)...${NC}"

ADMIN_DIR="$PROJECT_ROOT/admin-service"

# Check if node_modules exists
if [ ! -d "$ADMIN_DIR/node_modules" ]; then
    echo -e "   ${YELLOW}[SETUP] Installing admin dependencies...${NC}"
    (cd "$ADMIN_DIR" && npm install >> "$LOG_DIR/admin.log" 2>&1)
fi

# Clear old logs
> "$LOG_DIR/admin.log"

# Start admin dashboard
(
    cd "$ADMIN_DIR"
    echo "$(date): Starting Admin Dashboard on port 5176" >> "$LOG_DIR/admin.log"
    npx vite --port 5176 >> "$LOG_DIR/admin.log" 2>&1
) &
ADMIN_PID=$!
echo $ADMIN_PID > "$PID_DIR/admin.pid"
echo -e "${GREEN}[OK] Admin Dashboard started (PID: $ADMIN_PID)${NC}"

# Wait for admin
echo -n "   Waiting for admin dashboard"
for i in {1..30}; do
    if lsof -Pi :5176 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e " ${GREEN}Ready!${NC}"
        break
    fi

    # Check if process still running
    if ! kill -0 "$ADMIN_PID" 2>/dev/null; then
        echo -e " ${RED}Failed!${NC}"
        echo -e "   ${RED}[ERROR] Admin Dashboard process died. Check logs:${NC}"
        echo -e "   ${YELLOW}tail -30 $LOG_DIR/admin.log${NC}"
        tail -20 "$LOG_DIR/admin.log"
        cleanup
    fi

    if [ $i -eq 30 ]; then
        echo -e " ${RED}Timeout!${NC}"
        echo -e "   ${YELLOW}Check logs: tail -f $LOG_DIR/admin.log${NC}"
        tail -20 "$LOG_DIR/admin.log"
        cleanup
    fi
    echo -n "."
    sleep 1
done

# ============ Flutter Web ============
echo -e "${BLUE}[START] Starting Flutter Web (port 8080)...${NC}"
cd "$PROJECT_ROOT/flutter-app"

# Clean Chrome cache
rm -rf .dart_tool/chrome-device 2>/dev/null || true

# Summary before Flutter starts
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║    All Services Started!               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}[URLS]${NC}"
echo -e "  Backend:    ${YELLOW}http://localhost:8000${NC}"
echo -e "  API Docs:   ${YELLOW}http://localhost:8000/docs${NC}"
echo -e "  AI Service: ${YELLOW}http://localhost:8001${NC}"
echo -e "  Admin:      ${YELLOW}http://localhost:5176${NC}"
echo -e "  Flutter:    ${YELLOW}http://localhost:8080${NC} (starting...)"
echo ""
echo -e "${BLUE}[LOGS]${NC}"
echo -e "  Backend:    ${YELLOW}tail -f $LOG_DIR/backend.log${NC}"
echo -e "  AI:         ${YELLOW}tail -f $LOG_DIR/ai-service.log${NC}"
echo -e "  Admin:      ${YELLOW}tail -f $LOG_DIR/admin.log${NC}"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Start Flutter in foreground (keeps script running)
flutter run -d chrome --web-port=8080
