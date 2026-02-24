# LexiLingo System Testing Tools

Bộ công cụ kiểm thử độc lập để test các hệ thống AI của LexiLingo.

## 📦 Danh sách công cụ

### 1. **Dual-Stream Tester** (`dual-stream-tester.html`)
Kiểm thử real-time streaming STT/TTS với WebSocket.

**Tính năng:**
- ✅ WebSocket connection management
- ✅ Real-time audio recording & streaming
- ✅ STT partial & final transcripts
- ✅ TTS audio playback
- ✅ Interruption handling test
- ✅ Latency monitoring
- ✅ Message log viewer

**Cách dùng:**
1. Mở file `dual-stream-tester.html` trong trình duyệt
2. Đảm bảo AI service đang chạy ở `localhost:8001`
3. Click **Connect** để kết nối WebSocket
4. Click **Start Recording** để bắt đầu thu âm
5. Nói vào microphone để test STT
6. Xem responses trong message log

**Test cases:**
- Nói liên tục để test streaming STT
- Ngắt giữa chừng để test interruption handling
- Kiểm tra latency (target: <200ms first audio output)

---

### 2. **GraphCAG Tester** (`graphcag-tester.html`)
Kiểm thử Knowledge Graph, Cache, và LangGraph workflows.

**Tính năng:**
- 🧠 **GraphCAG Pipeline**: Test full AI analysis pipeline
- 🗺️ **Knowledge Graph**: Query concepts, relationships, learning paths
- 💾 **Cache Testing**: Test Redis cache operations (get/set/delete)
- 🔄 **LangGraph Flow**: Test workflow orchestration & node execution

**Cách dùng:**

#### Tab 1: GraphCAG Pipeline
1. Nhập student input (ví dụ: "I go to school yesterday")
2. Chọn topic và difficulty level
3. Click **Run GraphCAG Pipeline**
4. Xem kết quả analysis với feedback

#### Tab 2: Knowledge Graph
1. Chọn query type:
   - **Get Concept**: Lấy thông tin 1 concept
   - **Get Related**: Tìm concepts liên quan
   - **Get Examples**: Lấy ví dụ về concept
   - **Find Learning Path**: Tìm learning path
2. Nhập concept name (ví dụ: `present_simple`, `past_tense`)
3. Click **Query Knowledge Graph**

#### Tab 3: Cache Testing
1. Nhập cache key (ví dụ: `test_query_001`)
2. Nhập JSON value để cache
3. Set TTL (time to live in seconds)
4. Test các operations:
   - **Set Cache**: Lưu vào Redis
   - **Get Cache**: Lấy ra từ Redis
   - **Delete**: Xóa key

#### Tab 4: LangGraph Flow
1. Chọn workflow type:
   - **Analyze**: Phân tích student input
   - **Diagnose**: Chẩn đoán lỗi
   - **Feedback**: Generate feedback
   - **Full Pipeline**: Chạy toàn bộ flow
2. Nhập student input và context
3. Click **Execute Workflow**
4. Xem node execution timeline

---

## 🚀 Khởi động Backend

Trước khi dùng test tools, cần chạy AI service:

```bash
cd /path/to/LexiLingo/ai-service

# Activate Python environment
source /path/to/venv/bin/activate

# Set environment variables
export GEMINI_API_KEY='your-api-key'

# Run AI service
python -m uvicorn api.main:app --host 0.0.0.0 --port 8001 --reload
```

Kiểm tra service đã chạy:
```bash
curl http://localhost:8001/health
```

---

## 📊 Performance Targets

### Dual-Stream
| Metric | Target | Notes |
|--------|--------|-------|
| First audio output | <200ms | TTS streaming starts before full response |
| Interruption response | <100ms | VAD detection + TTS stop |
| Context switch | <50ms | Thinking pause/resume |

### GraphCAG
| Metric | Target | Notes |
|--------|--------|-------|
| Cache hit latency | <10ms | Redis lookup |
| Cache miss latency | <50ms | KG query + LLM generation |
| KG query time | <30ms | KuzuDB cypher query |
| Full pipeline | <500ms | End-to-end analysis |

---

## 🧪 Test Scenarios

### Scenario 1: Streaming Conversation
**Dual-Stream Tester**

1. Connect to WebSocket
2. Start recording
3. Say: "Hello, can you help me with English grammar?"
4. Wait for AI response (audio should start playing)
5. Interrupt mid-response by speaking again
6. Check logs for interruption handling

**Expected:**
- Partial transcripts appear during speaking
- Final transcript appears when paused
- AI starts thinking immediately
- Audio plays back smoothly
- Interruption stops audio and starts new transcript

---

### Scenario 2: Knowledge Graph Query
**GraphCAG Tester → Knowledge Graph Tab**

1. Query type: **Get Concept**
2. Concept name: `present_simple`
3. Click Query

**Expected:**
```json
{
  "concept": "present_simple",
  "definition": "Used for habits, facts, and general truths",
  "examples": [
    "I go to school every day",
    "She likes coffee"
  ],
  "related_concepts": ["present_continuous", "habits", "daily_routines"]
}
```

---

### Scenario 3: Cache Performance
**GraphCAG Tester → Cache Tab**

1. Set cache with key `grammar_query_present_simple`
2. Get cache multiple times
3. Check metrics for hit rate

**Expected:**
- First SET: ~5-10ms
- Subsequent GETs: <2ms (Redis is fast!)
- Cache metrics update correctly

---

### Scenario 4: Full Pipeline
**GraphCAG Tester → GraphCAG Pipeline Tab**

1. Input: "He go to the store yesterday"
2. Topic: "English Grammar - Past Tense"
3. Difficulty: Intermediate
4. Run pipeline

**Expected:**
```json
{
  "analysis": {
    "errors": [
      {
        "type": "verb_form",
        "incorrect": "go",
        "correct": "went",
        "explanation": "Past tense requires irregular verb form"
      }
    ]
  },
  "feedback": "Good try! Remember that 'go' changes to 'went' in past tense...",
  "examples": ["I went to school", "She went home"],
  "cache_hit": false,
  "latency_ms": 450
}
```

---

## 🐛 Troubleshooting

### WebSocket connection failed
**Problem:** Cannot connect to `ws://localhost:8001`

**Solutions:**
1. Check AI service is running: `curl http://localhost:8001/health`
2. Check WebSocket endpoint exists: Look for `/ws/conversation/stream` in `ai-service/api/routes/websocket_stream.py`
3. Check CORS settings in `main.py`

---

### Microphone access denied
**Problem:** Browser blocks microphone access

**Solutions:**
1. Use **HTTPS** (required for mic in Chrome)
2. Or use `localhost` (allowed for testing)
3. Check browser permissions: `chrome://settings/content/microphone`

---

### Cache operations fail
**Problem:** Redis connection error

**Solutions:**
1. Check Redis is running: `redis-cli ping`
2. Start Redis: `redis-server`
3. Check connection string in AI service config

---

### GraphCAG API returns 404
**Problem:** Endpoints not found

**Solutions:**
1. Check API routes are registered in `main.py`
2. Look at available endpoints: `http://localhost:8001/docs`
3. Verify endpoint paths match those in test tool

---

## 📝 Adding Custom Tests

### Example: Test new workflow node

1. Open `graphcag-tester.html`
2. Add new workflow type in `<select id="workflowType">`:
```html
<option value="my_custom_node">My Custom Node</option>
```

3. Backend must implement endpoint:
```python
@router.post("/ai/workflow/my_custom_node")
async def my_custom_node(request: WorkflowRequest):
    # Your implementation
    return {"result": "..."}
```

---

## 📚 API Reference

### Dual-Stream WebSocket

**Endpoint:** `ws://localhost:8001/ws/conversation/stream?session_id=xxx&user_id=xxx`

**Client → Server:**
- Binary audio chunks (PCM 16kHz mono, webm format)

**Server → Client:**

| Message Type | Description | Example |
|--------------|-------------|---------|
| `connected` | Connection established | `{"type": "connected", "session_id": "..."}` |
| `transcript_partial` | Intermediate STT | `{"type": "transcript_partial", "text": "Hello"}` |
| `transcript_final` | Complete utterance | `{"type": "transcript_final", "text": "Hello there"}` |
| `thinking_start` | AI started processing | `{"type": "thinking_start"}` |
| `thinking_stop` | AI stopped | `{"type": "thinking_stop", "reason": "interrupted"}` |
| `response_text` | Tutor text | `{"type": "response_text", "text": "..."}` |
| `response_audio_start` | Audio stream begins | `{"type": "response_audio_start"}` |
| Binary | Audio chunks | WAV format audio data |
| `response_audio_end` | Audio complete | `{"type": "response_audio_end"}` |
| `error` | Error occurred | `{"type": "error", "message": "..."}` |

---

### GraphCAG REST API

**Base URL:** `http://localhost:8001`

#### 1. Analyze Student Input
```http
POST /ai/analyze
Content-Type: application/json

{
  "text": "I go to school yesterday",
  "topic": "Past Tense",
  "difficulty": "intermediate",
  "user_id": "user123",
  "session_id": "session456"
}
```

#### 2. Knowledge Graph Query
```http
POST /ai/kg/concept
Content-Type: application/json

{
  "concept": "present_simple",
  "depth": 2
}
```

#### 3. Cache Operations
```http
# Set cache
POST /ai/cache/set
{
  "key": "test_key",
  "value": {"data": "..."},
  "ttl": 3600
}

# Get cache
GET /ai/cache/get?key=test_key

# Delete cache
DELETE /ai/cache/delete?key=test_key
```

#### 4. LangGraph Workflow
```http
POST /ai/workflow/analyze
Content-Type: application/json

{
  "input": "He go to school",
  "context": {
    "topic": "present_tense",
    "level": "beginner"
  }
}
```

---

## 🎯 Next Steps

1. **Open test tools** in browser
2. **Start AI service** (`uvicorn api.main:app --port 8001`)
3. **Run test scenarios** following examples above
4. **Monitor performance** via stats dashboard
5. **Report issues** if latencies exceed targets

---

## 📞 Support

**Issues:** Create issue in LexiLingo GitHub repo  
**Docs:** Check `/docs` folder for architecture details  
**API Docs:** Visit `http://localhost:8001/docs` when service is running

---

> **Version:** 1.0  
> **Last Updated:** 2026-02-03  
> **Author:** LexiLingo AI Team
