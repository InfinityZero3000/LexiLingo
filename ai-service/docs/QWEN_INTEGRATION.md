# Qwen Engine Integration - Quick Start

## What Was Implemented

The Qwen2.5-1.5B engine is now fully integrated into the LexiLingo AI service:

✅ **Files Created**:
- `api/services/qwen_engine.py` (482 lines)
- `scripts/test_qwen.py` (test suite)

✅ **Features**:
- 5 task-specific prompts (fluency, vocabulary, grammar, dialogue, comprehensive)
- LoRA adapter support via PEFT
- Structured JSON output parsing
- Fallback placeholder for development without model
- Async/await API
- Quantization support (8-bit/4-bit)
- Device management (CPU/GPU/auto)

✅ **Integration**:
- Updated `orchestrator.py` to load and call Qwen engine
- Added `peft==0.7.1` to `requirements.txt`
- Graceful fallback if model not available

## How to Use

### Option 1: Development Mode (Without Model)

The system works out-of-the-box without downloading the model - it will use placeholder responses:

```bash
cd ai-service
uvicorn api.main:app --reload
```

Test the endpoint:
```bash
curl -X POST http://localhost:8000/api/v1/ai/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I goes to school yesterday",
    "session_id": "test-123",
    "input_type": "text",
    "learner_profile": {"level": "A2"}
  }'
```

### Option 2: With Actual Qwen Model

**Step 1: Install dependencies**
```bash
pip install -r requirements.txt
```

**Step 2: Download the model**

Using Hugging Face CLI:
```bash
# Install HF CLI
pip install huggingface-hub

# Login (if model requires authentication)
huggingface-cli login

# Download Qwen2.5-1.5B-Instruct
huggingface-cli download Qwen/Qwen2.5-1.5B-Instruct
```

Or let the engine download it automatically on first run (will cache to `~/.cache/huggingface/`).

**Step 3: Configure `.env`**

Add to `ai-service/.env`:
```bash
# Qwen Model Configuration
QWEN_MODEL_NAME=Qwen/Qwen2.5-1.5B-Instruct
QWEN_ADAPTER_PATH=  # Leave empty for base model, or path to LoRA adapter
QWEN_DEVICE=auto  # auto, cpu, cuda, cuda:0, etc.
QWEN_LOAD_IN_8BIT=true  # Use 8-bit quantization to save memory
```

**Step 4: Update `config.py`** (if needed)

Add settings to `api/core/config.py`:
```python
class Settings(BaseSettings):
    # ... existing settings ...
    
    # Qwen Configuration
    QWEN_MODEL_NAME: str = "Qwen/Qwen2.5-1.5B-Instruct"
    QWEN_ADAPTER_PATH: Optional[str] = None
    QWEN_DEVICE: str = "auto"
    QWEN_LOAD_IN_8BIT: bool = True
```

**Step 5: Test the engine**
```bash
cd ai-service
python scripts/test_qwen.py
```

Expected output:
```
✓ Engine object created
✓ Model loaded in 15.23s
✓ Using device: cpu
✓ All required fields present
✅ All tests completed!
```

**Step 6: Start the service**
```bash
uvicorn api.main:app --reload
```

The orchestrator will now use the actual Qwen model instead of placeholders.

## Testing

### Quick Test
```bash
# Basic test (without model)
python scripts/test_qwen.py

# Full test with benchmarks (with model)
python scripts/test_qwen.py --benchmark
```

### Integration Test
```bash
# Test via API
curl -X POST http://localhost:8000/api/v1/ai/analyze \
  -H "Content-Type: application/json" \
  -d '{
    "text": "I goes to school yesterday with my friend",
    "session_id": "test-session",
    "input_type": "text",
    "learner_profile": {"level": "A2"}
  }'
```

Expected response:
```json
{
  "text": "Good try! The correct form is 'I went to school yesterday with my friend'...",
  "analysis": {
    "fluency": 0.85,
    "grammar": {
      "errors": [{"error": "goes", "correction": "went", "type": "past_tense"}],
      "corrected": "I went to school yesterday with my friend"
    },
    "vocabulary": "B1"
  },
  "score": {"fluency": 0.85, "grammar": 0.7, "overall": 0.78},
  "confidence": 0.92,
  "metadata": {
    "processing_time_ms": 124,
    "models_used": ["qwen"],
    "cached": false
  }
}
```

## Performance Targets

| Metric | Target | Expected (Base Model) | Expected (with LoRA) |
|--------|--------|----------------------|---------------------|
| Latency | < 150ms | 100-150ms | 100-150ms |
| Memory | ~1.6GB | ~1.6GB (base) | ~1.7GB (base + adapter) |
| Quality | - | Good | Excellent |

## LoRA Fine-Tuning (Optional)

To train a custom LoRA adapter:

1. Prepare training dataset (see `docs/TRAINING_README.md`)
2. Run training script in `DL-Model-Support/`
3. Save adapter to `models/qwen/unified_lora/`
4. Update `.env`: `QWEN_ADAPTER_PATH=./models/qwen/unified_lora`

The adapter will be auto-loaded on engine initialization.

## Next Steps

✅ **Completed**: Qwen engine implementation  
🟡 **Next**: Download and test with actual model  
⚪ **Future**: Train LoRA adapter for ESL tasks

See `implementation_plan.md` for full roadmap.

## Troubleshooting

**Error: "ImportError: No module named 'peft'"**
```bash
pip install peft==0.7.1
```

**Error: "Model not found"**
```bash
# Download manually
huggingface-cli download Qwen/Qwen2.5-1.5B-Instruct
```

**Error: "CUDA out of memory"**
```bash
# Use CPU or quantization
export QWEN_DEVICE=cpu
export QWEN_LOAD_IN_8BIT=true
```

**Slow inference (> 500ms)**
- Enable GPU: `QWEN_DEVICE=cuda`
- Use quantization: `QWEN_LOAD_IN_8BIT=true`
- Check cache is working: Look for `cached: true` in responses
