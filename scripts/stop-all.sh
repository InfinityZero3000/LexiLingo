#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_DIR="$PROJECT_ROOT/.pids"

echo -e "${BLUE}Stopping All Services${NC}"

# Stop application processes by PID files
for f in "$PID_DIR"/*.pid; do
  [ -f "$f" ] || continue
  PID=$(cat "$f")
  if kill -0 $PID 2>/dev/null; then
    kill -TERM $PID 2>/dev/null
    # Wait for graceful shutdown
    for i in {1..5}; do
      kill -0 $PID 2>/dev/null || break
      sleep 1
    done
    # Force kill if still running
    kill -9 $PID 2>/dev/null || true
  fi
  rm -f "$f"
done

# Stop Python processes on ports (avoid killing Docker daemon)
for PORT in 8000 8001 8080; do
  for PID in $(lsof -ti:$PORT 2>/dev/null); do
    # Check if it's a Python process (not Docker backend)
    if ps -p $PID -o command= | grep -q python; then
      echo -e "  Stopping Python process on port $PORT (PID: $PID)"
      kill -9 $PID 2>/dev/null || true
    fi
  done
done

# Stop Docker containers if Docker is running
if command -v docker &> /dev/null; then
  if docker info &> /dev/null; then
    echo -e "${YELLOW}Stopping Docker containers...${NC}"
    cd "$PROJECT_ROOT"
    
    # Try docker-compose down first
    if [ -f "docker-compose.yml" ]; then
      docker-compose down 2>/dev/null || true
    fi
    
    # Force stop specific LexiLingo containers
    for CONTAINER in lexilingo-backend-service lexilingo-ai-service lexilingo-postgres lexilingo-mongodb lexilingo-redis; do
      if docker ps -q -f name="$CONTAINER" 2>/dev/null | grep -q .; then
        echo -e "  Stopping ${CONTAINER}..."
        docker stop "$CONTAINER" 2>/dev/null || true
      fi
    done
  fi
fi

echo -e "${GREEN}All services stopped${NC}"
