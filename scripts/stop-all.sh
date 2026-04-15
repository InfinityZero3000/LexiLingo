#!/bin/bash
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}Stopping services (ports + containers, no remove)${NC}"

# Stop project processes bound to known service ports.
for PORT in 8000 8001 5176 8080; do
  for PID in $(lsof -ti:$PORT 2>/dev/null); do
    CMD=$(ps -p $PID -o command= 2>/dev/null)
    if echo "$CMD" | grep -Eq "python|node|dart|flutter|uvicorn|vite"; then
      echo -e "  Stopping process on port $PORT (PID: $PID, CMD: $CMD)"
      kill -TERM $PID 2>/dev/null || true
      sleep 1
      kill -9 $PID 2>/dev/null || true
    fi
  done
done

# Stop Docker containers if Docker is running
if command -v docker &> /dev/null; then
  if docker info &> /dev/null; then
    echo -e "${YELLOW}Stopping Docker containers...${NC}"
    cd "$PROJECT_ROOT"
    
    # Stop compose services without removing containers/networks/volumes.
    if [ -f "docker-compose.yml" ]; then
      docker compose stop 2>/dev/null || docker-compose stop 2>/dev/null || true
    fi
    
    # Stop known LexiLingo containers if they are still running.
    for CONTAINER in lexilingo-backend-service lexilingo-ai-service lexilingo-postgres lexilingo-mongodb lexilingo-redis; do
      if docker ps -q -f name="$CONTAINER" 2>/dev/null | grep -q .; then
        echo -e "  Stopping ${CONTAINER}..."
        docker stop "$CONTAINER" 2>/dev/null || true
      fi
    done
  else
    echo -e "${YELLOW}Docker daemon is not running${NC}"
  fi
else
  echo -e "${YELLOW}Docker is not installed${NC}"
fi

echo -e "${GREEN}Done: ports stopped and containers stopped without deletion${NC}"
