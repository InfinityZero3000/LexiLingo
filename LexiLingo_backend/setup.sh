#!/bin/bash

# LexiLingo Backend Quick Start Script

echo "🚀 Starting LexiLingo Backend Setup..."

# Check if .env exists
if [ ! -f ".env" ]; then
    echo "📝 Creating .env from example..."
    cp .env.example .env
    echo "⚠️  Please edit .env with your API keys!"
    echo "   - GEMINI_API_KEY"
    echo "   - MONGODB_URI (if using Atlas)"
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📥 Installing dependencies..."
pip install -r requirements.txt

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the server:"
echo "  1. Make sure MongoDB is running (docker-compose up -d mongodb)"
echo "  2. Run: uvicorn api.main:app --reload"
echo ""
echo "Or use Docker Compose:"
echo "  docker-compose up -d"
echo ""
