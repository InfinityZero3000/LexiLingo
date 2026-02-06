#!/bin/bash
# Quick health check for MCP Server

echo "======================================"
echo "  MCP Server Health Check"
echo "======================================"
echo ""

# 1. Check Ollama Service
echo "1. Ollama Service:"
if ps aux | grep -q "[o]llama serve"; then
    echo "   ✅ Running"
    
    # Check API
    if curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo "   ✅ API Responsive"
    else
        echo "   ❌ API Not Responding"
    fi
else
    echo "   ❌ Not Running"
    echo "   Fix: Run 'ollama serve' in background"
fi
echo ""

# 2. Check Models
echo "2. Available Models:"
if command -v ollama > /dev/null 2>&1; then
    ollama list | grep -E "qwen3-lexi|qwen3:8b" | while read line; do
        echo "   ✅ $line"
    done
else
    echo "   ❌ Ollama command not found"
fi
echo ""

# 3. Check Config
echo "3. MCP Configuration:"
if [ -f "config.yaml" ]; then
    echo "   ✅ config.yaml found"
    
    # Check if Python available
    if command -v python3 > /dev/null 2>&1; then
        QWEN_MODEL=$(python3 -c "from utils.config import Config; c = Config.load('config.yaml'); print(c.get('models.qwen.model', 'N/A'))" 2>/dev/null || echo "N/A")
        FALLBACK=$(python3 -c "from utils.config import Config; c = Config.load('config.yaml'); print(c.get('features.enable_fallback', 'N/A'))" 2>/dev/null || echo "N/A")
        
        echo "   - Qwen Model: $QWEN_MODEL"
        echo "   - Fallback: $FALLBACK"
    fi
else
    echo "   ❌ config.yaml not found"
fi
echo ""

# 4. Check Dependencies
echo "4. Dependencies:"
if command -v pip > /dev/null 2>&1 || command -v pip3 > /dev/null 2>&1; then
    PIP_CMD=$(command -v pip3 > /dev/null 2>&1 && echo "pip3" || echo "pip")
    
    if $PIP_CMD show httpx > /dev/null 2>&1; then
        echo "   ✅ httpx installed"
    else
        echo "   ❌ httpx not installed"
        echo "   Fix: pip install httpx"
    fi
else
    echo "   ⚠️  pip not found"
fi
echo ""

# 5. Check Gemini API Key
echo "5. Gemini API Key:"
if [ -n "$GEMINI_API_KEY" ]; then
    echo "   ✅ Set (${#GEMINI_API_KEY} chars)"
else
    echo "   ⚠️  Not set (fallback won't work)"
    echo "   Fix: export GEMINI_API_KEY='your-key'"
fi
echo ""

# Summary
echo "======================================"
echo "  Summary"
echo "======================================"

# Count issues
ISSUES=0

# Check critical items
ps aux | grep -q "[o]llama serve" || ((ISSUES++))
ollama list | grep -q "qwen3-lexi" || ((ISSUES++))
[ -f "config.yaml" ] || ((ISSUES++))

if [ $ISSUES -eq 0 ]; then
    echo "✅ MCP Server is READY"
    echo ""
    echo "To start:"
    echo "  python server.py"
else
    echo "⚠️  Found $ISSUES issue(s)"
    echo ""
    echo "Please fix issues above before starting"
fi

echo "======================================"
