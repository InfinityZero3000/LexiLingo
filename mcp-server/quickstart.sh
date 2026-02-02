#!/bin/bash

# Quick Start Script for LexiLingo MCP Server

set -e

echo "=================================="
echo "LexiLingo MCP Server - Quick Start"
echo "=================================="
echo ""

# Check Python version
echo "[1/6] Checking Python version..."
python3 --version || {
    echo "Python 3.10+ required"
    exit 1
}

# Create virtual environment if not exists
if [ ! -d "venv" ]; then
    echo "[2/6] Creating virtual environment..."
    python3 -m venv venv
else
    echo "[2/6] Virtual environment already exists"
fi

# Activate virtual environment
echo "[3/6] Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "[4/6] Installing dependencies..."
pip install --quiet --upgrade pip
pip install --quiet -r requirements.txt

# Create necessary directories
echo "[5/6] Creating directories..."
mkdir -p logs data tests handlers

# Check environment variables
echo "[6/6] Checking environment..."
if [ -z "$GEMINI_API_KEY" ]; then
    echo "⚠️  GEMINI_API_KEY not set. Gemini model will not work."
    echo "   Set it with: export GEMINI_API_KEY='your_key'"
else
    echo "✅ GEMINI_API_KEY found"
fi

echo ""
echo "=================================="
echo "✅ Setup complete!"
echo "=================================="
echo ""
echo "To start the MCP server:"
echo "  python server.py"
echo ""
echo "To run tests:"
echo "  pytest tests/ -v"
echo ""
