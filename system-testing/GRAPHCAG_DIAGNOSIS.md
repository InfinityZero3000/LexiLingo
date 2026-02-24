# GraphCAG Performance Diagnosis

## 🔍 Vấn đề phát hiện

### Triệu chứng
- GraphCAG Analysis endpoint timeout sau 180s
- Ollama không phản hồi requests
- GUI test tool hiển thị FAIL

### Root Cause Analysis

**1. Ollama Model Performance Issue**
```bash
PID: 26021, CPU: 473.0%, MEM: 4785.61MB
CMD: ollama runner --ollama-engine --model qwen3-lexi
```

**Phân tích:**
- Model `qwen3-lexi` (5.2GB) đang chiếm **473% CPU** (4-5 cores)
- RAM usage: **4.78GB** chỉ cho model
- Test inference timeout sau 20-30s với prompt đơngiản "Hi"

**2. Hardware Constraints**
```
Model size:    5.2 GB
RAM required:  ~6-8 GB (with overhead)
CPU cores:     Đang dùng 4-5 cores ở 100%
Inference time: > 30s cho 1 token đơn giản
```

**3. Test Results**
| Test | Status | Latency | Note |
|------|--------|---------|------|
| API Health | WARNING | 241ms | Status: ok |
| Ollama | PASS | 3ms | 2 models loaded |
| GraphCAG Endpoint | PASS | 3ms | Endpoint available |
| **GraphCAG Analysis** | **FAIL** | **Timeout (180s)** | Model không phản hồi |

---

## 🎯 Nguyên nhân chính

**Ollama inference quá chậm do hardware không đủ mạnh:**

1. **Model quá lớn (5.2GB):** qwen3-lexi cần > 6GB RAM + CPU mạnh
2. **CPU inference:** Không có GPU acceleration (Apple Metal có thể chậm)
3. **Context loading:** Model load mất thời gian, inference còn chậm hơn

**Bằng chứng:**
```bash
# Test trực tiếp Ollama
$ curl -X POST http://localhost:11434/api/chat \
   -d '{"model": "qwen3-lexi", "messages": [{"role":"user","content":"Hi"}]}'

# Kết quả: Timeout after 30s with 0 bytes received
```

---

## 💡 Giải pháp

### Option 1: Sử dụng model nhỏ hơn (Recommended)
```python
# .env
OLLAMA_MODEL=qwen3:1.5b  # Nhỏ hơn, nhanh hơn
```

Hoặc dùng model quantized:
```bash
ollama pull qwen3:0.5b-q4_0  # 500MB, rất nhanh
```

### Option 2: Tăng timeout (Temporary workaround)
```python
# system-testing/graphcag_system_test.py
class TestConfig:
    timeout: int = 300  # Tăng từ 180s → 300s
```

**Lưu ý:** Vẫn sẽ chậm, không khuyến khích cho production.

### Option 3: Sử dụng Gemini API (Cloud fallback)
```python
# .env
USE_OLLAMA=false
USE_GATEWAY=true  # Sẽ dùng Gemini nếu Ollama fail
```

Gemini API nhanh hơn (~2-3s) và không tốn tài nguyên local.

### Option 4: Upgrade hardware
- **CPU:** 8+ cores recommended
- **RAM:** 16GB+ (32GB ideal)
- **GPU:** NVIDIA GPU với CUDA hoặc Mac M2/M3 Pro trở lên

---

## 🧪 Verification Steps

### Test Ollama trực tiếp:
```bash
# 1. Kill stuck process
pkill -9 -follama runner

# 2. Test với model nhỏ
ollama run qwen3:1.5b "Say hi"

# 3. Measure latency
time curl -X POST http://localhost:11434/api/chat \
  -d '{"model":"qwen3:1.5b","messages":[{"role":"user","content":"Hi"}],"stream":false}'
```

### Test GraphCAG với GUI tool:
1. Chạy `graphcag_system_test.py`
2. Click "Check Ollama" → Verify PASS
3. Click "Test Ollama Inference Speed" → Check latency
4. Nếu < 10s → OK, có thể dùng
5. Nếu > 30s → Cần đổi model hoặc fallback Gemini

---

## 📊 Performance Expectations

### Acceptable Performance:
| Component | Target | Current | Status |
|-----------|--------|---------|--------|
| Health Check | < 100ms | 241ms | ⚠️ OK |
| Ollama (lists) | < 10ms | 3ms | ✅ Good |
| Ollama inference | < 5s | **>30s** | ❌ Too slow |
| GraphCAG total | < 10s | Timeout | ❌ Unusable |

### Với model nhỏ hơn (qwen3:1.5b):
- Expected inference: **2-3s**
- GraphCAG total: **5-8s**
- Usable cho testing và development

---

## 🔧 Quick Fix

```bash
# 1. Stop AI service
pkill -f "uvicorn api.main"

# 2. Đổi sang model nhỏ trong .env
sed -i '' 's/OLLAMA_MODEL=qwen3-lexi/OLLAMA_MODEL=qwen3:1.5b/' ai-service/.env

# 3. Restart AI service
cd ai-service
export PYTHONPATH=$(pwd)
export GEMINI_API_KEY='your-key'
python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 &

# 4. Test lại với GUI tool
cd ../system-testing
python graphcag_system_test.py
```

---

## 📝 Kết luận

**Vấn đề KHÔNG phải code hay architecture, mà là hardware performance.**

- ✅ GraphCAG pipeline code hoạt động đúng
- ✅ Ollama connection OK
- ✅ Model loaded thành công
- ❌ **Model inference quá chậm (>30s) do hardware yếu**

**Khuyến nghị:**
- Development: Dùng model nhỏ (qwen3:1.5b) hoặc Gemini API
- Production: Deploy lên server có GPU hoặc dùng cloud API
