#!/bin/bash

###############################################################################
# Stop AI Service and Cloudflare Tunnel
# Usage: bash scripts/stop-ai-local.sh
###############################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$PROJECT_ROOT/logs"
AI_PORT=8001

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Stopping LexiLingo AI Service & Tunnel            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Stop by PID files
if [ -f "$LOG_DIR/ai-local.pid" ]; then
    AI_PID=$(cat "$LOG_DIR/ai-local.pid")
    if ps -p $AI_PID > /dev/null 2>&1; then
        echo -e "${BLUE}→${NC} Stopping AI Service (PID: $AI_PID)..."
        kill $AI_PID 2>/dev/null || true
        rm "$LOG_DIR/ai-local.pid"
        echo -e "${GREEN}✓${NC} AI Service stopped"
    fi
fi

if [ -f "$LOG_DIR/tunnel.pid" ]; then
    TUNNEL_PID=$(cat "$LOG_DIR/tunnel.pid")
    if ps -p $TUNNEL_PID > /dev/null 2>&1; then
        echo -e "${BLUE}→${NC} Stopping Cloudflare Tunnel (PID: $TUNNEL_PID)..."
        kill $TUNNEL_PID 2>/dev/null || true
        rm "$LOG_DIR/tunnel.pid"
        rm "$LOG_DIR/tunnel-url.txt" 2>/dev/null || true
        echo -e "${GREEN}✓${NC} Tunnel stopped"
    fi
fi

# Force kill by port (fallback)
if lsof -Pi :$AI_PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo -e "${BLUE}→${NC} Force killing process on port $AI_PORT..."
    lsof -ti:$AI_PORT | xargs kill -9 2>/dev/null || true
fi

# Kill all cloudflared processes
if pgrep -x "cloudflared" > /dev/null; then
    echo -e "${BLUE}→${NC} Stopping all cloudflared processes..."
    pkill cloudflared 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓${NC} All services stopped"
