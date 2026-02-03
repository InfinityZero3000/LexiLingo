#!/bin/bash
# Quick start script - Start backend services only (faster)
# Flutter can be started separately

set -e
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load env
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Kill existing
echo -e "${YELLOW}🧹 Cleaning up...${NC}"
pkill -9 -f uvicorn 2>/dev/null || true
sleep 1

# Start Backend
echo -e "${GREEN}🔧 Starting Backend (port 8000)...${NC}"
cd "$PROJECT_ROOT/backend-service"
source venv/bin/activate
nohup python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 > "$PROJECT_ROOT/logs/backend.log" 2>&1 &
echo "   PID: $!"

# Start AI Service
echo -e "${GREEN}🤖 Starting AI Service (port 8001)...${NC}"
cd "$PROJECT_ROOT/ai-service"
source "$PROJECT_ROOT/.venv/bin/activate"
export GEMINI_API_KEY="${GEMINI_API_KEY}"
nohup python -m uvicorn api.main_lite:app --host 0.0.0.0 --port 8001 > "$PROJECT_ROOT/logs/ai-service.log" 2>&1 &
echo "   PID: $!"

# Wait for services
sleep 3

# Check health
echo ""
echo -e "${GREEN}📍 Checking services...${NC}"
curl -s http://localhost:8000/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'   Backend: {d[\"status\"]}')" 2>/dev/null || echo "   Backend: starting..."
curl -s http://localhost:8001/health | python3 -c "import sys,json; d=json.load(sys.stdin); print(f'   AI Service: {d[\"status\"]}')" 2>/dev/null || echo "   AI Service: starting..."

echo ""
echo -e "${GREEN}✅ Backend services started!${NC}"
echo ""
echo "📍 URLs:"
echo "   Backend:    http://localhost:8000"
echo "   API Docs:   http://localhost:8000/docs"
echo "   AI Service: http://localhost:8001"
echo "   AI Docs:    http://localhost:8001/docs"
echo ""
echo "📋 To start Flutter separately:"
echo "   cd flutter-app && flutter run -d chrome --web-port=8080"
echo ""
echo "📋 Logs:"
echo "   tail -f logs/backend.log"
echo "   tail -f logs/ai-service.log"
