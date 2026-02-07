#!/bin/bash

###############################################################################
# Start AI Service Locally with Cloudflare Tunnel
# Usage: bash scripts/start-ai-local.sh
###############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  LexiLingo AI Service - Local Deployment          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AI_SERVICE_DIR="$PROJECT_ROOT/ai-service"
VENV_PATH="$PROJECT_ROOT/.venv"
LOG_DIR="$PROJECT_ROOT/logs"
AI_PORT=8001

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Load environment variables
if [ -f "$AI_SERVICE_DIR/.env" ]; then
    echo -e "${GREEN}✓${NC} Loading environment variables..."
    export $(cat "$AI_SERVICE_DIR/.env" | grep -v '^#' | xargs)
else
    echo -e "${YELLOW}⚠${NC} Warning: .env file not found in ai-service/"
    echo "  Create one with: GEMINI_API_KEY=your_key_here"
fi

# Check if virtual environment exists
if [ ! -d "$VENV_PATH" ]; then
    echo -e "${RED}✗${NC} Virtual environment not found at $VENV_PATH"
    echo "  Run: python3 -m venv .venv && source .venv/bin/activate && pip install -r ai-service/requirements.txt"
    exit 1
fi

# Activate virtual environment
echo -e "${GREEN}✓${NC} Activating virtual environment..."
source "$VENV_PATH/bin/activate"

# Check if port is already in use
if lsof -Pi :$AI_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠${NC} Port $AI_PORT is already in use"
    read -p "Kill existing process and restart? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}→${NC} Killing process on port $AI_PORT..."
        lsof -ti:$AI_PORT | xargs kill -9 2>/dev/null || true
        sleep 2
    else
        echo "Exiting..."
        exit 1
    fi
fi

# Start AI Service
echo -e "${BLUE}→${NC} Starting AI Service on port $AI_PORT..."
cd "$AI_SERVICE_DIR"

# Start uvicorn in background
nohup python -m uvicorn api.main_lite:app \
    --host 0.0.0.0 \
    --port $AI_PORT \
    --log-level info \
    > "$LOG_DIR/ai-local.log" 2>&1 &

AI_PID=$!
echo -e "${GREEN}✓${NC} AI Service started (PID: $AI_PID)"

# Wait for service to be ready
echo -e "${BLUE}→${NC} Waiting for AI Service to be ready..."
for i in {1..30}; do
    if curl -s http://localhost:$AI_PORT/health > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} AI Service is ready!"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Check if cloudflared is installed
if ! command -v cloudflared &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Cloudflared not found. Installing..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        brew install cloudflare/cloudflare/cloudflared
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared-linux-amd64.deb
        rm cloudflared-linux-amd64.deb
    else
        echo -e "${RED}✗${NC} Unsupported OS. Please install cloudflared manually:"
        echo "  https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/install-and-setup/installation/"
        exit 1
    fi
fi

# Start Cloudflare Tunnel
echo -e "${BLUE}→${NC} Starting Cloudflare Tunnel..."
echo -e "${YELLOW}Note:${NC} This will create a temporary public URL (free, no account needed)"
echo ""

# Start tunnel in background
nohup cloudflared tunnel --url http://localhost:$AI_PORT \
    > "$LOG_DIR/tunnel.log" 2>&1 &

TUNNEL_PID=$!
echo -e "${GREEN}✓${NC} Tunnel started (PID: $TUNNEL_PID)"

# Wait for tunnel URL
echo -e "${BLUE}→${NC} Waiting for tunnel URL..."
sleep 5

# Extract tunnel URL from logs
TUNNEL_URL=$(grep -oP 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/tunnel.log" | head -1)

if [ -z "$TUNNEL_URL" ]; then
    # Try alternative log format
    TUNNEL_URL=$(tail -20 "$LOG_DIR/tunnel.log" | grep -oP 'https://[^\s]+\.trycloudflare\.com' | head -1)
fi

if [ -n "$TUNNEL_URL" ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           🎉 Deployment Successful! 🎉             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Local URL:${NC}  http://localhost:$AI_PORT"
    echo -e "${BLUE}Public URL:${NC} $TUNNEL_URL"
    echo ""
    echo -e "${YELLOW}⚠ IMPORTANT:${NC} Copy the Public URL and update:"
    echo "  1. backend-service/render.yaml → AI_SERVICE_URL"
    echo "  2. Render.com dashboard → Environment Variables"
    echo "  3. flutter-app/.env → AI_SERVICE_URL"
    echo ""
    echo -e "${BLUE}Test endpoints:${NC}"
    echo "  Health: $TUNNEL_URL/health"
    echo "  Docs:   $TUNNEL_URL/docs"
    echo ""
    echo -e "${BLUE}Logs:${NC}"
    echo "  AI Service: tail -f $LOG_DIR/ai-local.log"
    echo "  Tunnel:     tail -f $LOG_DIR/tunnel.log"
    echo ""
    echo -e "${BLUE}Stop services:${NC}"
    echo "  kill $AI_PID $TUNNEL_PID"
    echo "  or: bash scripts/stop-ai-local.sh"
    echo ""
    
    # Save PIDs for stop script
    echo "$AI_PID" > "$LOG_DIR/ai-local.pid"
    echo "$TUNNEL_PID" > "$LOG_DIR/tunnel.pid"
    echo "$TUNNEL_URL" > "$LOG_DIR/tunnel-url.txt"
    
else
    echo -e "${RED}✗${NC} Failed to get tunnel URL. Check logs:"
    echo "  cat $LOG_DIR/tunnel.log"
    exit 1
fi

# Keep script running (optional - comment out if you want to run in background)
# echo ""
# echo -e "${BLUE}Press Ctrl+C to stop all services${NC}"
# trap "kill $AI_PID $TUNNEL_PID 2>/dev/null; echo 'Stopped'; exit 0" INT
# wait
