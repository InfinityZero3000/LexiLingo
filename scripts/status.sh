#!/bin/bash

# ================================================
# LexiLingo - Check Service Status
# ================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   LexiLingo - Service Status           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check Backend (Port 8000)
echo -e "${BLUE}🔧 Backend Service (Port 8000):${NC}"
if lsof -ti:8000 > /dev/null 2>&1; then
    PID=$(lsof -ti:8000)
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo -e "   ${GREEN}✅ RUNNING${NC} (PID: $PID)"
        echo -e "   URL: http://localhost:8000"
        echo -e "   Docs: http://localhost:8000/docs"
    else
        echo -e "   ${YELLOW}⚠️  PORT IN USE${NC} but not responding (PID: $PID)"
    fi
else
    echo -e "   ${RED}❌ STOPPED${NC}"
fi
echo ""

# Check AI Service (Port 8001)
echo -e "${BLUE}🤖 AI Service (Port 8001):${NC}"
if lsof -ti:8001 > /dev/null 2>&1; then
    PID=$(lsof -ti:8001)
    if curl -s http://localhost:8001/health > /dev/null 2>&1; then
        echo -e "   ${GREEN}✅ RUNNING${NC} (PID: $PID)"
        echo -e "   URL: http://localhost:8001"
    else
        echo -e "   ${YELLOW}⚠️  PORT IN USE${NC} but not responding (PID: $PID)"
    fi
else
    echo -e "   ${RED}❌ STOPPED${NC}"
fi
echo ""

# Check Flutter Web (Port 8080)
echo -e "${BLUE}📱 Flutter Web (Port 8080):${NC}"
if lsof -ti:8080 > /dev/null 2>&1; then
    PID=$(lsof -ti:8080)
    echo -e "   ${GREEN}✅ RUNNING${NC} (PID: $PID)"
    echo -e "   URL: http://localhost:8080"
else
    echo -e "   ${RED}❌ STOPPED${NC}"
fi
echo ""

# Check Database
echo -e "${BLUE}🗄️  PostgreSQL Database:${NC}"
if pg_isready > /dev/null 2>&1; then
    echo -e "   ${GREEN}✅ RUNNING${NC}"
    if psql -lqt | cut -d \| -f 1 | grep -qw lexilingo; then
        echo -e "   Database 'lexilingo': ${GREEN}EXISTS${NC}"
    else
        echo -e "   Database 'lexilingo': ${RED}NOT FOUND${NC}"
    fi
else
    echo -e "   ${RED}❌ NOT RUNNING${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}════════════════════════════════════════${NC}"
RUNNING_COUNT=0
TOTAL_COUNT=4

lsof -ti:8000 > /dev/null 2>&1 && ((RUNNING_COUNT++))
lsof -ti:8001 > /dev/null 2>&1 && ((RUNNING_COUNT++))
lsof -ti:8080 > /dev/null 2>&1 && ((RUNNING_COUNT++))
pg_isready > /dev/null 2>&1 && ((RUNNING_COUNT++))

if [ $RUNNING_COUNT -eq $TOTAL_COUNT ]; then
    echo -e "${GREEN}✅ All services are running ($RUNNING_COUNT/$TOTAL_COUNT)${NC}"
elif [ $RUNNING_COUNT -eq 0 ]; then
    echo -e "${RED}❌ No services running ($RUNNING_COUNT/$TOTAL_COUNT)${NC}"
    echo -e "\n${YELLOW}Run: ./scripts/start-all.sh to start all services${NC}"
else
    echo -e "${YELLOW}⚠️  Some services running ($RUNNING_COUNT/$TOTAL_COUNT)${NC}"
    echo -e "\n${YELLOW}Run: ./scripts/start-all.sh to start missing services${NC}"
fi
echo ""
