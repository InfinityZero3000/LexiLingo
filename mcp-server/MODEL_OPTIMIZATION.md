# 🚀 Model Loading Optimization Guide

## Vấn đề hiện tại

**Vấn đề**: Qwen model (5.2GB) mất 30-60s để load lần đầu tiên
**Nguyên nhân**: Ollama phải load model từ disk vào RAM/VRAM

## ✅ Giải pháp đề xuất

### 1. **Keep Model Warm** (Khuyến nghị ⭐⭐⭐⭐⭐)

Giữ model luôn trong memory, không unload giữa các requests.

**Implementation:**

```yaml
# config.yaml
models:
  qwen:
    keep_alive: "24h"  # Giữ model trong 24h
    # Hoặc: "-1" = forever (không bao giờ unload)
```

**Ollama Configuration:**
```bash
# Set keep_alive trong mỗi request
{
  "model": "qwen3-lexi",
  "keep_alive": "24h",  # Giữ 24 giờ
  "prompt": "..."
}
```

**Lợi ích:**
- ✅ Response time: 30-60s → 2-5s
- ✅ Không cần load lại
- ✅ Zero latency cho requests tiếp theo

**Trade-off:**
- ⚠️ RAM/VRAM usage: ~6-8GB constant
- ⚠️ Không giải phóng memory cho apps khác

---

### 2. **Pre-warming Script** (Startup) ⭐⭐⭐⭐

Load model ngay khi server start, không đợi request đầu tiên.

**File: `prewarm_models.sh`**
```bash
#!/bin/bash
# Pre-warm Ollama models on server start

echo "🔥 Pre-warming models..."

# Send dummy request to load model
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3-lexi",
  "prompt": "warmup",
  "keep_alive": "24h",
  "stream": false
}' > /dev/null 2>&1

echo "✅ Model warmed up and kept alive"
```

**Usage:**
```bash
# Start Ollama
ollama serve &

# Wait for Ollama to be ready
sleep 2

# Pre-warm models
./prewarm_models.sh

# Start MCP server
python server.py
```

---

### 3. **Systemd Service with Pre-warming** ⭐⭐⭐⭐⭐

Tự động start và pre-warm khi máy boot.

**File: `/etc/systemd/system/lexilingo-mcp.service`**
```ini
[Unit]
Description=LexiLingo MCP Server with Ollama
After=network.target

[Service]
Type=simple
User=yourusername
WorkingDirectory=/path/to/mcp-server
Environment="GEMINI_API_KEY=your_key"

# Start Ollama first
ExecStartPre=/usr/local/bin/ollama serve
ExecStartPre=/bin/sleep 5
ExecStartPre=/path/to/mcp-server/prewarm_models.sh

# Start MCP server
ExecStart=/usr/bin/python3 /path/to/mcp-server/server.py

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Enable:**
```bash
sudo systemctl enable lexilingo-mcp
sudo systemctl start lexilingo-mcp
```

---

### 4. **Use Smaller Model** (Development) ⭐⭐⭐

Dùng model nhỏ hơn cho dev/testing.

**Options:**
```bash
# Qwen 1.5B (faster, less accurate)
ollama pull qwen:1.5b
# Load time: ~5-10s instead of 30-60s

# Qwen 4B (balance)
ollama pull qwen:4b
# Load time: ~15-20s
```

**Config for environment-based:**
```yaml
# config.yaml
models:
  qwen:
    model: "${QWEN_MODEL:-qwen3-lexi}"  # Default to qwen3-lexi
    
# For development:
# export QWEN_MODEL="qwen:1.5b"

# For production:
# export QWEN_MODEL="qwen3-lexi"
```

---

### 5. **Optimize Ollama Settings** ⭐⭐⭐⭐

Tune Ollama parameters cho performance.

**Ollama Environment Variables:**
```bash
# In start_server.sh or .env

# Increase concurrent model loading
export OLLAMA_NUM_PARALLEL=4

# Keep models in memory longer
export OLLAMA_KEEP_ALIVE=24h

# Use more GPU layers (faster inference)
export OLLAMA_GPU_LAYERS=35

# Optimize context size (smaller = faster)
export OLLAMA_CONTEXT_SIZE=2048
```

---

### 6. **Model Caching Strategy** ⭐⭐⭐

Implement response caching để giảm số lần gọi model.

**Implementation:**
```python
# handlers/qwen.py

import hashlib
from typing import Optional

class QwenHandler:
    def __init__(self, config):
        self.cache = {}  # Simple in-memory cache
        self.cache_ttl = 3600  # 1 hour
        # ... existing code
    
    def _get_cache_key(self, prompt: str, context: dict) -> str:
        """Generate cache key"""
        cache_str = f"{prompt}:{context.get('user_level', '')}"
        return hashlib.md5(cache_str.encode()).hexdigest()
    
    async def chat(self, message: str, context: dict):
        # Check cache first
        cache_key = self._get_cache_key(message, context)
        if cache_key in self.cache:
            cached = self.cache[cache_key]
            if time.time() - cached['timestamp'] < self.cache_ttl:
                logger.info("[QwenHandler] Cache hit")
                return cached['response']
        
        # Generate response (existing code)
        response = await self._generate_response(message, context)
        
        # Cache result
        self.cache[cache_key] = {
            'response': response,
            'timestamp': time.time()
        }
        
        return response
```

---

### 7. **Connection Pooling** ⭐⭐⭐

Reuse HTTP connections để giảm latency.

**Current Code:**
```python
# Already using persistent client
self.client = httpx.AsyncClient(
    base_url=self.base_url,
    timeout=self.timeout,
)
```

**Optimize:**
```python
self.client = httpx.AsyncClient(
    base_url=self.base_url,
    timeout=self.timeout,
    limits=httpx.Limits(
        max_keepalive_connections=5,
        max_connections=10,
        keepalive_expiry=30.0
    )
)
```

---

## 🎯 Recommended Setup (Production)

### Optimal Configuration:

```yaml
# config.yaml
models:
  qwen:
    provider: "ollama"
    model: "qwen3-lexi"
    base_url: "http://localhost:11434"
    keep_alive: "24h"        # ← Keep warm
    max_tokens: 512
    temperature: 0.7
    timeout: 120
    retry_attempts: 2

features:
  enable_cache: true          # ← Enable response cache
  cache_ttl: 3600
```

### Startup Script:

```bash
#!/bin/bash
# start_production.sh

# 1. Set environment
export OLLAMA_KEEP_ALIVE="24h"
export OLLAMA_NUM_PARALLEL=4
export GEMINI_API_KEY="your_key"

# 2. Start Ollama (if not running)
if ! pgrep -x "ollama" > /dev/null; then
    echo "Starting Ollama..."
    ollama serve > /dev/null 2>&1 &
    sleep 5
fi

# 3. Pre-warm model
echo "Pre-warming model..."
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3-lexi",
  "prompt": "warmup",
  "keep_alive": "24h"
}' > /dev/null

# 4. Wait for model to load
sleep 30

# 5. Verify model loaded
if ollama ps | grep -q "qwen3-lexi"; then
    echo "✅ Model loaded and ready"
else
    echo "⚠️  Model not loaded, may be slow on first request"
fi

# 6. Start MCP server
echo "Starting MCP server..."
python server.py
```

---

## 📊 Performance Comparison

| Setup | First Request | Subsequent | Memory | Recommendation |
|-------|--------------|------------|--------|----------------|
| **Default (cold)** | 30-60s | 30-60s | 0 → 6GB | ❌ Not for production |
| **Keep Alive** | 30-60s | 2-5s | 6GB constant | ✅ Good |
| **Pre-warmed** | 2-5s | 2-5s | 6GB constant | ⭐ Best |
| **+ Cache** | 2-5s | <100ms | 6GB + cache | ⭐⭐ Optimal |
| **Smaller Model** | 5-10s | 1-2s | 2-3GB | 🔧 Dev/test |

---

## 🚀 Quick Implementation

### Step 1: Update config
```bash
cd mcp-server
# Add keep_alive to config.yaml (already in instructions above)
```

### Step 2: Create pre-warm script
```bash
cat > prewarm_models.sh << 'EOF'
#!/bin/bash
echo "🔥 Pre-warming qwen3-lexi..."
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3-lexi",
  "prompt": "Hi",
  "keep_alive": "24h"
}' > /dev/null
echo "✅ Model warmed"
EOF

chmod +x prewarm_models.sh
```

### Step 3: Update start script
```bash
# Edit start_server.sh to include pre-warming
```

### Step 4: Test
```bash
# Start Ollama
ollama serve &

# Pre-warm
./prewarm_models.sh

# Verify loaded
ollama ps | grep qwen3-lexi

# Start server
python server.py
```

---

## 💡 Best Practices

1. **Production**: Pre-warm + keep_alive="24h"
2. **Development**: Smaller model or accept cold start
3. **High traffic**: Pre-warm + response caching
4. **Memory limited**: Dynamic loading with smart caching
5. **Multi-model**: Stagger pre-warming to avoid memory spike

---

## 🔍 Monitoring

### Check if model is loaded:
```bash
ollama ps
# Output should show qwen3-lexi with time loaded
```

### Check memory usage:
```bash
# Linux
free -h

# macOS
vm_stat | grep "Pages active"
```

### Monitor response times:
```python
# In your logs
[QwenHandler] ✅ Generated response (1234 chars) in 2.3s
```

---

## 📌 Summary

**Fastest Setup (Recommended):**
```
1. Set keep_alive: "24h" in config
2. Pre-warm on startup
3. Keep Ollama running 24/7
4. Add response caching for common queries

Result: 
- First request: ~2-5s (pre-warmed)
- Subsequent: ~2-5s
- Cached: <100ms
```

**Cost:**
- Memory: 6-8GB constant
- Worth it: ✅ Yes for production
