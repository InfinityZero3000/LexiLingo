#!/bin/bash
# Test optimization performance

echo "======================================"
echo "  Performance Test"
echo "======================================"
echo ""

OLLAMA_URL="http://localhost:11434"
MODEL="qwen3-lexi"

# Check if model is loaded
echo "1. Checking if model is pre-loaded..."
if ollama ps | grep -q "$MODEL"; then
    echo "   ✅ Model is loaded (should be fast)"
    ollama ps | grep "$MODEL"
else
    echo "   ⚠️  Model NOT loaded (will be slow first time)"
    echo "   Run: ./prewarm_models.sh"
fi
echo ""

# Test response time
echo "2. Testing response time..."
echo "   Sending test request..."

START=$(date +%s)

RESPONSE=$(curl -s "$OLLAMA_URL/api/generate" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"$MODEL\",
        \"prompt\": \"What is 2+2?\",
        \"stream\": false,
        \"keep_alive\": \"24h\",
        \"options\": {
            \"num_predict\": 20
        }
    }")

END=$(date +%s)
DURATION=$((END - START))

echo ""
echo "3. Results:"
echo "   Duration: ${DURATION}s"

if [ $DURATION -lt 10 ]; then
    echo "   Status: ✅ FAST (optimized)"
    echo "   Expected: Model was pre-loaded"
elif [ $DURATION -lt 30 ]; then
    echo "   Status: ⚠️  MEDIUM (not optimal)"
    echo "   Expected: Model loading or system busy"
else
    echo "   Status: ❌ SLOW (not optimized)"
    echo "   Expected: Model not pre-loaded"
    echo "   Fix: Run ./prewarm_models.sh"
fi

# Extract response
RESPONSE_TEXT=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('response', 'error'))" 2>/dev/null || echo "Could not parse")

echo ""
echo "   Response: ${RESPONSE_TEXT:0:100}..."
echo ""

# Check if model stayed loaded
echo "4. Checking if model stayed loaded..."
if ollama ps | grep -q "$MODEL"; then
    echo "   ✅ Model still loaded (will be fast next time)"
    
    # Show until time
    UNTIL=$(ollama ps | grep "$MODEL" | awk '{print $NF " " $(NF-1) " " $(NF-2)}')
    echo "   Until: $UNTIL"
else
    echo "   ❌ Model unloaded (check keep_alive setting)"
fi
echo ""

# Performance summary
echo "======================================"
echo "  Performance Summary"
echo "======================================"

if [ $DURATION -lt 10 ]; then
    echo "✅ OPTIMIZATION WORKING"
    echo "   - Response time: ${DURATION}s (target: <10s)"
    echo "   - Model kept warm: Yes"
    echo "   - Ready for production: Yes"
else
    echo "⚠️  OPTIMIZATION NOT WORKING"
    echo "   - Response time: ${DURATION}s (too slow)"
    echo "   - Model kept warm: Unknown"
    echo "   - Action needed: Run ./prewarm_models.sh"
fi

echo ""
