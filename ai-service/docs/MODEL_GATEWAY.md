# ModelGateway - Unified AI Model Management

## Tổng quan

ModelGateway là hệ thống quản lý AI models cho LexiLingo với các tính năng:

- **Lazy Loading**: Models chỉ load khi được gọi lần đầu
- **Auto Unload**: Tự động giải phóng RAM khi model idle
- **Smart Routing**: Tự động route request đến model phù hợp
- **Health Monitoring**: Theo dõi trạng thái và metrics

## Kiến trúc

```
┌─────────────────────────────────────────────────────────────┐
│                     MODEL GATEWAY                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐        │
│  │   REGISTRY  │   │   LOADER    │   │  SCHEDULER  │        │
│  │  (metadata) │   │(lazy load)  │   │(auto unload)│        │
│  └──────┬──────┘   └──────┬──────┘   └──────┬──────┘        │
│         │                 │                 │               │
│         └─────────────────┼─────────────────┘               │
│                           │                                 │
│                    ┌──────┴──────┐                          │
│                    │   ROUTER    │                          │
│                    │(smart route)│                          │
│                    └──────┬──────┘                          │
│                           │                                 │
│    ┌──────────────────────┼──────────────────────┐          │
│    ▼           ▼          ▼          ▼           ▼          │
│ ┌──────┐  ┌──────┐   ┌──────┐   ┌──────┐   ┌──────┐         │
│ │ Qwen │  │Whispr│   │ Piper│   │HuBERT│   │Gemini│         │
│ │(chat)│  │(stt) │   │(tts) │   │(pron)│   │(cloud)│        │
│ └──────┘  └──────┘   └──────┘   └──────┘   └──────┘         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Cấu trúc thư mục

```
ai-service/api/services/
├── model_gateway.py        # Core gateway class
├── gateway_setup.py        # Setup và registration
└── handlers/
    ├── __init__.py
    ├── qwen_handler.py     # Chat/Grammar
    ├── whisper_handler.py  # Speech-to-Text
    ├── piper_handler.py    # Text-to-Speech
    ├── hubert_handler.py   # Pronunciation
    └── gemini_handler.py   # Cloud fallback
```

## Models và Memory

| Model | Task | RAM | Priority | Idle Timeout |
|-------|------|-----|----------|--------------|
| Qwen3-1.7B | Chat, Grammar | ~3.5GB | CRITICAL | 10 phút |
| Whisper-base | STT | ~500MB | NORMAL | 5 phút |
| Piper | TTS | ~100MB | NORMAL | 5 phút |
| HuBERT-large | Pronunciation | ~2GB | LOW | 3 phút |
| Gemini API | Fallback | ~10MB | HIGH | 30 phút |

## Sử dụng

### 1. Khởi tạo Gateway (trong main.py)

```python
from api.services.gateway_setup import setup_gateway, shutdown_gateway

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    await setup_gateway(
        max_memory_mb=8000,
        enable_auto_unload=True,
        use_gemini_fallback=True,
    )
    
    yield
    
    # Shutdown
    await shutdown_gateway()
```

### 2. Thực thi Task

```python
from api.services.gateway_setup import execute_task

# Chat
result = await execute_task(
    task_type="chat",
    params={
        "text": "Hello, I want learn English",
        "system_prompt": "You are an English tutor",
    }
)

# Grammar Analysis
result = await execute_task(
    task_type="grammar",
    params={"text": "I goes to school yesterday"}
)

# Speech-to-Text
result = await execute_task(
    task_type="stt",
    params={"audio": audio_bytes_or_path}
)

# Text-to-Speech
result = await execute_task(
    task_type="tts",
    params={"text": "Hello, how are you?"}
)

# Pronunciation Analysis
result = await execute_task(
    task_type="pronunciation",
    params={
        "audio": audio_bytes,
        "reference_text": "Hello world"
    }
)
```

### 3. Direct Gateway Access

```python
from api.services.model_gateway import get_gateway

gateway = await get_gateway()

# Invoke specific model
result = await gateway.invoke(
    model_name="qwen",
    method="invoke",
    params={"task": "chat", "text": "Hello"}
)

# Get status
status = gateway.get_status()
print(f"Loaded models: {status['loaded_models']}")
print(f"Memory used: {status['gateway']['used_memory_mb']}MB")
```

## Task Types & Routing

| Task Type | Routed Model | Method |
|-----------|--------------|--------|
| `chat` | qwen | chat |
| `grammar` | qwen | analyze_grammar |
| `response` | qwen | generate_response |
| `stt`, `transcribe` | whisper | transcribe |
| `tts`, `synthesize` | piper | synthesize |
| `pronunciation` | hubert | analyze_pronunciation |
| `explain_vi`, `vietnamese` | gemini | explain_vietnamese |

## Cấu hình qua Environment Variables

```bash
# Memory
MAX_MEMORY_MB=8000

# Qwen
QWEN_MODEL_PATH=models/qwen3-1.7b
QWEN_MODEL_ID=Qwen/Qwen2.5-1.5B-Instruct

# Whisper
WHISPER_MODEL_SIZE=base
WHISPER_MODEL_PATH=models/whisper

# Piper
PIPER_MODEL_PATH=models/piper/en_US-lessac-medium.onnx
PIPER_VOICE=en_US-lessac-medium

# HuBERT
HUBERT_MODEL_ID=facebook/hubert-large-ls960-ft

# Gemini
GEMINI_API_KEY=your_api_key

# Device
MODEL_DEVICE=auto  # cpu, cuda, mps, auto
```

## GraphCAG Integration

GraphCAG nodes đã được update để sử dụng ModelGateway:

```python
# nodes_v2.py
async def diagnose_node(state: GraphCAGState) -> Dict[str, Any]:
    gateway = await get_gateway()
    
    result = await gateway.execute_task(
        task_type="chat",
        params={
            "text": state.get("user_input", ""),
            "system_prompt": DIAGNOSIS_PROMPT,
        }
    )
    
    if result.get("success"):
        return parse_diagnosis(result["data"])
    
    # Fallback to rule-based
    return _rule_based_diagnosis(state)
```

## Flow Diagram

```
User Request
     │
     ▼
┌─────────────┐
│ execute_task│
└──────┬──────┘
       │ route()
       ▼
┌─────────────┐
│   ROUTER    │──────────────────────────────────────┐
└──────┬──────┘                                      │
       │                                             │
       ├─── chat ───▶ [Qwen] ◄── lazy load if needed│
       │                                             │
       ├─── stt ────▶ [Whisper] ◄── lazy load       │
       │                                             │
       ├─── tts ────▶ [Piper] ◄── lazy load         │
       │                                             │
       └─── pron ───▶ [HuBERT] ◄── lazy load        │
                                                     │
       If primary fails ────────────────────────────┘
       │                                             
       ▼                                             
    [Gemini Fallback]                                
       │                                             
       ▼                                             
   Response                                          
```

## Monitoring

Kiểm tra trạng thái gateway qua health endpoint:

```bash
curl http://localhost:8001/health
```

Response:
```json
{
  "status": "healthy",
  "gateway_initialized": true,
  "gateway_status": {
    "gateway": {
      "uptime_seconds": 3600,
      "total_requests": 150,
      "max_memory_mb": 8000,
      "used_memory_mb": 4200
    },
    "loaded_models": ["qwen", "gemini"],
    "models": {
      "qwen": {
        "status": "ready",
        "request_count": 120,
        "avg_latency_ms": 450
      }
    }
  }
}
```

## Troubleshooting

### Model không load được

1. Kiểm tra path và permissions
2. Kiểm tra RAM available
3. Xem logs: `docker logs ai-service`

### Memory exhausted

1. Giảm `MAX_MEMORY_MB`
2. Giảm `idle_timeout_seconds` để unload nhanh hơn
3. Set model priority thấp hơn

### Fallback to Gemini quá nhiều

1. Kiểm tra local model có hoạt động không
2. Tăng timeout
3. Kiểm tra GEMINI_API_KEY

## Contributing

Khi thêm model mới:

1. Tạo handler trong `handlers/`
2. Register trong `gateway_setup.py`
3. Thêm task routing nếu cần
4. Update documentation
