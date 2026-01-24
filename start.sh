#!/bin/bash

# LexiLingo - Quick Start Script
# This script helps you quickly set up and run the LexiLingo microservices

set -e

echo "=================================================="
echo "   LexiLingo Microservices - Quick Start"
echo "=================================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠️  .env file not found. Creating from template...${NC}"
    cp .env.example .env
    echo -e "${GREEN}✅ .env file created${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT: Edit .env file with your credentials:${NC}"
    echo "   1. SECRET_KEY - Generate with: openssl rand -hex 32"
    echo "   2. GEMINI_API_KEY - Get from: https://aistudio.google.com/app/apikey"
    echo ""
    read -p "Press Enter after editing .env file..."
fi

# Check Docker
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker Desktop.${NC}"
    exit 1
fi

# Check Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}❌ Docker is not running. Please start Docker Desktop.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Docker is running${NC}"
echo ""

# Ask what to do
echo "What would you like to do?"
echo "1) Start all services (PostgreSQL + MongoDB + Redis + Backend + AI)"
echo "2) Start only Backend Service (Port 8000)"
echo "3) Start only AI Service (Port 8001)"
echo "4) Stop all services"
echo "5) View logs"
echo "6) Clean restart (remove all data)"
echo ""
read -p "Enter choice [1-6]: " choice

case $choice in
    1)
        echo ""
        echo -e "${YELLOW}Starting all services...${NC}"
        docker-compose up -d
        echo ""
        echo -e "${GREEN}✅ All services started!${NC}"
        echo ""
        echo "Services available at:"
        echo "  - Backend Service: http://localhost:8000/docs"
        echo "  - AI Service: http://localhost:8001/docs"
        echo "  - PostgreSQL: localhost:5432"
        echo "  - MongoDB: localhost:27017"
        echo "  - Redis: localhost:6379"
        echo ""
        echo "View logs: docker-compose logs -f"
        ;;
    2)
        echo ""
        echo -e "${YELLOW}Starting Backend Service...${NC}"
        docker-compose up -d postgres backend-service
        echo ""
        echo -e "${GREEN}✅ Backend Service started!${NC}"
        echo "  - Docs: http://localhost:8000/docs"
        ;;
    3)
        echo ""
        echo -e "${YELLOW}Starting AI Service...${NC}"
        docker-compose up -d mongodb redis ai-service
        echo ""
        echo -e "${GREEN}✅ AI Service started!${NC}"
        echo "  - Docs: http://localhost:8001/docs"
        ;;
    4)
        echo ""
        echo -e "${YELLOW}Stopping all services...${NC}"
        docker-compose down
        echo ""
        echo -e "${GREEN}✅ All services stopped${NC}"
        ;;
    5)
        echo ""
        echo "Showing logs (Ctrl+C to exit)..."
        docker-compose logs -f
        ;;
    6)
        echo ""
        echo -e "${RED}⚠️  WARNING: This will delete all data!${NC}"
        read -p "Are you sure? [y/N]: " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            echo ""
            echo -e "${YELLOW}Stopping and removing all containers and volumes...${NC}"
            docker-compose down -v
            echo ""
            echo -e "${GREEN}✅ Clean restart complete${NC}"
            echo ""
            echo "Starting fresh..."
            docker-compose up -d
        else
            echo "Cancelled."
        fi
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo "=================================================="
echo "   Commands:"
echo "=================================================="
echo "  docker-compose up -d          # Start all"
echo "  docker-compose down            # Stop all"
echo "  docker-compose logs -f         # View logs"
echo "  docker-compose ps              # List services"
echo ""
