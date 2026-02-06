#!/bin/bash

# LexiLingo System Testing - Quick Start Script
# This script opens both testing tools in your default browser

echo "🚀 LexiLingo System Testing - Quick Start"
echo "=========================================="
echo ""

# Get the directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if files exist
if [ ! -f "$SCRIPT_DIR/dual-stream-tester.html" ]; then
    echo "❌ Error: dual-stream-tester.html not found"
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/graphcag-tester.html" ]; then
    echo "❌ Error: graphcag-tester.html not found"
    exit 1
fi

echo "✅ Test tools found"
echo ""

# Check if AI service is running
echo "🔍 Checking AI service at localhost:8001..."
if curl -s http://localhost:8001/health > /dev/null 2>&1; then
    echo "✅ AI service is running"
else
    echo "⚠️  Warning: AI service is not responding at localhost:8001"
    echo "   Please start the AI service first:"
    echo "   cd /path/to/LexiLingo/ai-service"
    echo "   source venv/bin/activate"
    echo "   export GEMINI_API_KEY='your-key'"
    echo "   python -m uvicorn api.main_lite:app --host 0.0.0.0 --port 8001"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo ""
echo "🌐 Opening test tools in browser..."
echo ""

# Detect OS and open browser
case "$OSTYPE" in
    darwin*)
        # macOS
        echo "📱 Opening Dual-Stream Tester..."
        open "$SCRIPT_DIR/dual-stream-tester.html"
        sleep 1
        
        echo "📱 Opening GraphCAG Tester..."
        open "$SCRIPT_DIR/graphcag-tester.html"
        ;;
    linux*)
        # Linux
        echo "📱 Opening Dual-Stream Tester..."
        xdg-open "$SCRIPT_DIR/dual-stream-tester.html" > /dev/null 2>&1
        sleep 1
        
        echo "📱 Opening GraphCAG Tester..."
        xdg-open "$SCRIPT_DIR/graphcag-tester.html" > /dev/null 2>&1
        ;;
    msys*|cygwin*|win*)
        # Windows
        echo "📱 Opening Dual-Stream Tester..."
        start "$SCRIPT_DIR/dual-stream-tester.html"
        sleep 1
        
        echo "📱 Opening GraphCAG Tester..."
        start "$SCRIPT_DIR/graphcag-tester.html"
        ;;
    *)
        echo "❌ Unsupported OS: $OSTYPE"
        echo "Please open the following files manually in your browser:"
        echo "  - $SCRIPT_DIR/dual-stream-tester.html"
        echo "  - $SCRIPT_DIR/graphcag-tester.html"
        exit 1
        ;;
esac

echo ""
echo "✅ Test tools opened successfully!"
echo ""
echo "📚 Quick Tips:"
echo "  • Dual-Stream Tester: Test WebSocket streaming STT/TTS"
echo "  • GraphCAG Tester: Test Knowledge Graph, Cache, LangGraph"
echo ""
echo "📖 For detailed instructions, see README.md"
echo ""
