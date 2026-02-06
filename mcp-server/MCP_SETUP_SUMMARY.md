# MCP Server Configuration Summary

## ✅ Cấu hình đã hoàn thành

### 1. **Qwen Model Integration** (Local - MIỄN PHÍ)
- **Model**: `qwen3-lexi` (8.2B parameters, Q4_K_M quantization)
- **Provider**: Ollama (chạy local trên máy bạn)
- **Status**: ✅ Configured và ready
- **Chi phí**: **KHÔNG mất phí** - hoàn toàn miễn phí
- **Location**: `/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/ai-service/models/qwen3/`

### 2. **Gemini Fallback** (Cloud API - CÓ PHÍ)
- **Model**: `gemini-1.5-flash`
- **Provider**: Google Cloud API
- **Status**: ✅ Configured as fallback only
- **Chi phí**: 
  - Input: ~$0.075 / 1M tokens
  - Output: ~$0.30 / 1M tokens
  - Free tier: 15 req/min, 1M tokens/day

### 3. **Priority & Fallback Logic** ✅
```
┌─────────────────────────────────────┐
│   User Request                      │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Try Qwen (Local - Free)           │
│   - Model: qwen3-lexi               │
│   - Via: Ollama API                 │
│   - Timeout: 120s                   │
└──────────────┬──────────────────────┘
               │
               ├─ Success → Return response
               │
               └─ Failed ↓
                         
┌─────────────────────────────────────┐
│   ⚠️  WARNING TRIGGERED              │
│   "QWEN MODEL UNAVAILABLE"          │
│   "Fix: Run 'ollama serve'"         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Fallback to Gemini (Cloud - Paid) │
│   ⚠️  "Using Gemini API fallback"    │
│   ⚠️  "(may incur costs)"            │
└──────────────┬──────────────────────┘
               │
               ├─ Success → Return response
               │
               └─ Failed → Error (both failed)
```

## 📋 Các thay đổi chính

### 1. Config File ([mcp-server/config.yaml](mcp-server/config.yaml))
```yaml
models:
  qwen:
    provider: "ollama"
    model: "qwen3-lexi"
    base_url: "http://localhost:11434"
    timeout: 120  # First load needs time for 5GB model
    
  gemini:
    provider: "api"
    fallback_only: true  # Only use when Qwen fails

features:
  enable_fallback: true
  warn_on_fallback: true  # ⚠️  Cảnh báo khi dùng fallback
```

### 2. QwenHandler ([mcp-server/handlers/qwen.py](mcp-server/handlers/qwen.py))
- ✅ Integrate với Ollama API qua httpx
- ✅ Retry logic (2 attempts)
- ✅ Connection testing khi khởi tạo
- ✅ Model availability verification

### 3. Chat Tool ([mcp-server/tools/chat.py](mcp-server/tools/chat.py))
- ✅ Priority: Qwen first, Gemini fallback
- ✅ Warning messages khi Qwen fail:
  ```
  ⚠️  QWEN MODEL UNAVAILABLE: [error]
  ⚠️  Reason: Ollama might not be running
  ⚠️  Fix: Run 'ollama serve' and ensure 'qwen3-lexi' is available
  ```
- ✅ Warning khi dùng fallback:
  ```
  ⚠️  Using Gemini API fallback (may incur costs)
  ```

### 4. Dependencies ([mcp-server/requirements.txt](mcp-server/requirements.txt))
- ✅ Added `httpx>=0.25.0` for Ollama API calls

## 🎯 Cách sử dụng

### Start MCP Server
```bash
cd mcp-server
python server.py
```

### Chat với MCP (auto priority)
```python
# Tự động thử Qwen trước, fallback Gemini nếu cần
{
    "tool": "chat_with_ai",
    "args": {
        "message": "What is the difference between affect and effect?",
        "context": {
            "user_level": "B2",
            "session_id": "abc123"
        }
        # model không cần chỉ định, mặc định dùng qwen
    }
}
```

### Force model cụ thể
```python
# Force dùng Qwen (không fallback)
{"args": {"message": "...", "model": "qwen"}}

# Force dùng Gemini
{"args": {"message": "...", "model": "gemini"}}
```

## ⚙️ Yêu cầu hệ thống

### Qwen (Local)
- ✅ Ollama đã cài đặt và running
- ✅ Model `qwen3-lexi` đã load: `ollama list`
- ✅ Service running: `ps aux | grep ollama`
- ✅ RAM: ~6-8GB khi model được load

### Gemini (Fallback)
- ✅ API Key: `GEMINI_API_KEY` environment variable
- ✅ Internet connection

## 🔍 Kiểm tra trạng thái

### 1. Check Ollama
```bash
# Check service
ps aux | grep ollama

# Check models
ollama list

# Test API
curl http://localhost:11434/api/tags
```

### 2. Check MCP Config
```bash
cd mcp-server
python -c "from utils.config import Config; c = Config.load('config.yaml'); print(c.get('models.qwen'))"
```

### 3. Test Qwen Handler
```bash
cd mcp-server
python test_qwen_handler.py
```

## 🐛 Troubleshooting

### Vấn đề: Qwen timeout
**Nguyên nhân**: Lần đầu tiên model cần load vào memory (5.2GB)
**Giải pháp**: 
- Đợi ~30-60s cho lần đầu
- Tăng timeout trong config (đã set 120s)
- Hoặc pre-load model: `ollama run qwen3-lexi "test"`

### Vấn đề: Ollama not responding
**Kiểm tra**:
```bash
ollama serve  # Start nếu chưa chạy
ollama ps     # Check running models
```

### Vấn đề: Gemini fallback không work
**Kiểm tra**:
```bash
echo $GEMINI_API_KEY  # Check API key
```

## 📊 Chi phí dự kiến

### Qwen (Recommended)
- **Chi phí**: $0 (hoàn toàn miễn phí)
- **Tốc độ**: ~2-5s/response (sau khi loaded)
- **RAM**: ~6-8GB

### Gemini (Fallback Emergency)
- **Chi phí**: 
  - Trong free tier: $0 (giới hạn 1M tokens/day)
  - Ngoài free tier: ~$0.10-0.50 per 1000 responses
- **Tốc độ**: ~1-3s/response
- **RAM**: Minimal (cloud API)

## ✅ Kết luận

**MCP Server đã sẵn sàng** với:
1. ✅ Qwen local model ưu tiên (MIỄN PHÍ)
2. ✅ Gemini fallback chỉ khi cần (CÓ PHÍ)
3. ✅ Cảnh báo rõ ràng khi có vấn đề
4. ✅ Retry logic và error handling
5. ✅ Config linh hoạt và dễ customize

**Khuyến nghị**: Giữ Ollama chạy liên tục để tránh phải fallback sang Gemini (có phí).
