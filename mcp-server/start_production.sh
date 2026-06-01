#!/bin/bash
# Production startup script with optimizations

set -e

echo "======================================"
echo "  LexiLingo MCP - Production Start"
echo "======================================"
echo ""

# Configuration
export OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
export OLLAMA_KEEP_ALIVE="${OLLAMA_KEEP_ALIVE:-24h}"
export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-4}"
export GEMINI_API_KEY="${GEMINI_API_KEY:-AIzaSyAdneokZf4BO1wEEfarOIHlFCN0TJJdlbM}"

# Navigate to script directory
cd "$(dirname "$0")"

echo "📋 Configuration:"
echo "   - Ollama URL: $OLLAMA_URL"
echo "   - Keep Alive: $OLLAMA_KEEP_ALIVE"
echo "   - Parallel Models: $OLLAMA_NUM_PARALLEL"
echo "   - Gemini API: ${GEMINI_API_KEY:0:20}..."
echo ""

# Step 1: Check/Start Ollama
echo "1️⃣  Checking Ollama service..."
if ! ps aux | grep -q "[o]llama serve"; then
    echo "   ⚠️  Ollama not running, attempting to start..."
    
    if command -v ollama > /dev/null 2>&1; then
        nohup ollama serve > ollama.log 2>&1 &
        echo "   ✓ Started Ollama (PID: $!)"
        echo "   Waiting for Ollama to be ready..."
        sleep 5
    else
        echo "   ❌ Ollama command not found"
        echo "   Install from: https://ollama.ai"
        exit 1
    fi
else
    echo "   ✓ Ollama is running"
fi

# Wait for Ollama API
echo "   Waiting for API to be ready..."
for i in {1..30}; do
    if curl -s "$OLLAMA_URL/api/tags" > /dev/null 2>&1; then
        echo "   ✓ Ollama API is responsive"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "   ❌ Ollama API timeout"
        exit 1
    fi
    sleep 1
done
echo ""

# Step 2: Pre-warm models
echo "2️⃣  Pre-warming models..."
if [ -f "./prewarm_models.sh" ]; then
    chmod +x ./prewarm_models.sh
    ./prewarm_models.sh
else
    echo "   ⚠️  prewarm_models.sh not found, skipping"
    echo "   Model will be loaded on first request (slower)"
fi
echo ""

# Step 3: Verify model is loaded
echo "3️⃣  Verifying model status..."
if command -v ollama > /dev/null 2>&1; then
    if ollama ps | grep -q "qwen3-lexi"; then
        echo "   ✅ Model loaded and ready"
        ollama ps | head -3
    else
        echo "   ⚠️  Model not loaded yet"
        echo "   First request will take 30-60s"
    fi
else
    echo "   ℹ️  Cannot verify (ollama CLI not available)"
fi
echo ""

# Step 4: Check dependencies
echo "4️⃣  Checking Python dependencies..."
if python3 -c "import httpx" 2>/dev/null; then
    echo "   ✓ httpx installed"
else
    echo "   ⚠️  httpx not found, installing..."
    pip install httpx
fi

if python3 -c "import mcp" 2>/dev/null; then
    echo "   ✓ mcp installed"
else
    echo "   ⚠️  mcp package might be missing"
    echo "   Install with: pip install -r requirements.txt"
fi
echo ""

# Step 5: Health check
echo "5️⃣  Running health check..."
if [ -f "./health_check.sh" ]; then
    chmod +x ./health_check.sh
    ./health_check.sh | grep -E "✅|❌|⚠️"
else
    echo "   ℹ️  health_check.sh not found, skipping"
fi
echo ""

# Step 6: Start MCP Server
echo "======================================"
echo "  Starting MCP Server"
echo "======================================"
echo ""
echo "Server will start with:"
echo "  - Qwen model pre-loaded (fast responses)"
echo "  - Keep alive: $OLLAMA_KEEP_ALIVE"
echo "  - Gemini fallback enabled"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start the server
exec python3 server.py
