#!/bin/bash

# ===========================================
# LexiLingo Development Startup Script
# Starts Backend and Frontend (skips AI service)
# ===========================================

# KHÔNG dùng set -e vì có thể gây lỗi với background processes

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# PID tracking
BACKEND_PID=""
FLUTTER_PID=""

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}   LexiLingo Development Environment    ${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Function to check if port is in use
check_port() {
    lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1
}

# Function to kill process on port
kill_port() {
    if check_port $1; then
        echo -e "${YELLOW}⚠ Port $1 is in use, killing existing process...${NC}"
        lsof -ti :$1 | xargs kill -9 2>/dev/null || true
        sleep 2
    fi
}

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}🛑 Shutting down services...${NC}"
    
    # Kill backend
    if [ -n "$BACKEND_PID" ]; then
        kill $BACKEND_PID 2>/dev/null || true
    fi
    
    # Kill flutter
    if [ -n "$FLUTTER_PID" ]; then
        kill $FLUTTER_PID 2>/dev/null || true
    fi
    
    # Kill processes on ports
    kill_port 8000
    kill_port 8080
    
    echo -e "${GREEN}✅ All services stopped${NC}"
    exit 0
}

# Set trap for cleanup
trap cleanup SIGINT SIGTERM EXIT

# ============ START BACKEND SERVICE ============
echo -e "${GREEN}🚀 Starting Backend Service (port 8000)...${NC}"

kill_port 8000

BACKEND_DIR="$PROJECT_ROOT/backend-service"

# Check if venv exists
if [ ! -d "$BACKEND_DIR/venv" ]; then
    echo -e "${YELLOW}Creating virtual environment...${NC}"
    python3 -m venv "$BACKEND_DIR/venv"
fi

# Start backend trong subshell riêng biệt với đường dẫn tuyệt đối
(
    cd "$BACKEND_DIR"
    source venv/bin/activate
    pip install -q -r requirements.txt 2>/dev/null || true
    # Không dùng --reload để tránh vấn đề với WatchFiles
    python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 2>&1
) &
BACKEND_PID=$!

echo -e "${GREEN}✅ Backend starting (PID: $BACKEND_PID)${NC}"

# Wait for backend to be ready
echo -e "${BLUE}⏳ Waiting for backend to be ready...${NC}"
for i in {1..30}; do
    if check_port 8000; then
        echo -e "${GREEN}✅ Backend is ready!${NC}"
        break
    fi
    if ! kill -0 $BACKEND_PID 2>/dev/null; then
        echo -e "${RED}Backend process died! Check logs above.${NC}"
        break
    fi
    sleep 1
done

if ! check_port 8000; then
    echo -e "${YELLOW}⚠ Backend may not be ready yet, continuing anyway...${NC}"
fi

# ============ START FLUTTER WEB ============
echo ""
echo -e "${GREEN}🚀 Starting Flutter Web (port 8080)...${NC}"

kill_port 8080

FLUTTER_DIR="$PROJECT_ROOT/flutter-app"

# Clean Chrome cache to avoid issues
rm -rf "$FLUTTER_DIR/.dart_tool/chrome-device" 2>/dev/null || true

# Start Flutter trong subshell riêng biệt
(
    cd "$FLUTTER_DIR"
    flutter run -d chrome --web-port=8080 2>&1
) &
FLUTTER_PID=$!

echo -e "${GREEN}✅ Flutter Web starting (PID: $FLUTTER_PID)${NC}"

# ============ SHOW STATUS ============
echo ""
echo -e "${BLUE}=========================================${NC}"
echo -e "${GREEN}🎉 Services Started!${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""
echo -e "  ${BLUE}Backend API:${NC}  http://localhost:8000"
echo -e "  ${BLUE}API Docs:${NC}     http://localhost:8000/docs"
echo -e "  ${BLUE}Flutter Web:${NC}  http://localhost:8080"
echo ""
echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Wait for any background process to finish
wait
