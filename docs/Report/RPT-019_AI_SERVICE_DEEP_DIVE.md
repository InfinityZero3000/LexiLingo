# RPT-019 — AI Service Deep Dive: GraphCAG, Model Gateway & Tools

> **Cập nhật:** 2026-04-24 | **AI Service Version:** 2.1.0

---

## 1. Tổng Quan AI Service

AI Service (`ai-service/`) là bộ não của LexiLingo, cung cấp:
- **GraphCAG Pipeline** — tutor AI thông minh với Knowledge Graph
- **Model Gateway** — quản lý tập trung tất cả AI models
- **Smart Router** — định tuyến model thông minh
- **Voice Pipeline** — STT/TTS/Pronunciation analysis
- **Topic Chat** — chat theo chủ đề với context đặc biệt

**Stack chính:**
- FastAPI + Motor (MongoDB) + Redis
- LangGraph (orchestration) + KuzuDB (KG) + Sentence Transformers (embeddings)
- Whisper (STT) + Piper/gTTS (TTS) + HuBERT-large (pronunciation)
- Gemini API + Groq API + Ollama (local LLMs)
- PyTorch + PEFT/LoRA (custom Qwen model)

---

## 2. GraphCAG Pipeline — Phân Tích Chi Tiết

### 2.1 Khái Niệm Cốt Lõi

**GraphCAG = Graph (Knowledge Graph) + CAG (Cache-Augmented Generation)**

Khác với RAG truyền thống (tìm kiếm document), GraphCAG:
- **CAG**: Grounding LLM bằng cached learner context (Redis: profile, history)
- **Graph**: Mở rộng context bằng KuzuDB knowledge graph hops

### 2.2 StateGraph Architecture

```
File: ai-service/api/services/graph_cag/graph.py
```

```
[INPUT_NODE] ─── voice? ──▶ [STT_NODE] ─┐
      │                                  │
      └─────── text ─────────────────────┘
                                         │
                                   [CACHE_GATE_NODE]
                                         │
                    ┌────── hit ──────── END
                    │
                    └── miss ─▶ [KG_DIAGNOSE_NODE] (parallel)
                                    ├─ kg_expand_node
                                    └─ diagnose_node
                                         │
                         ┌───────────────┼───────────────┐
                         ▼               ▼               ▼
                  [ASK_CLARIFY]  [VIETNAMESE_NODE]  [RETRIEVE_NODE]
                         │               │                │
                         └───────────────┼────────────────┘
                                         ▼
                                  [GENERATE_NODE]
                                         │
                    ┌────── voice ───────┼─────── text
                    ▼                                ▼
           [PRONUNCIATION_NODE]                    END
                    │
                   END
```

### 2.3 Mô Tả Từng Node

| Node | File | Chức năng |
|------|------|-----------|
| `input_node` | `nodes_v2.py` | Load learner profile từ Redis, khởi tạo state |
| `cache_gate_node` | `nodes_v2.py` | RAPID cache check — reuse/patch/full decision |
| `stt_node` | `nodes_v2.py` | Transcribe audio → text qua Whisper |
| `kg_diagnose_node` | `nodes_v2.py` | Chạy kg_expand + diagnose song song (asyncio.gather) |
| `kg_expand_node` | `nodes_v2.py` | Map user input → KuzuDB concepts, graph hop expansion |
| `diagnose_node` | `nodes_v2.py` | AI grammar/fluency analysis, intent detection |
| `vietnamese_node` | `nodes_v2.py` | Giải thích tiếng Việt cho learner A1/A2 |
| `ask_clarify_node` | `nodes_v2.py` | Hỏi làm rõ khi confidence < 0.5 |
| `retrieve_node` | `nodes_v2.py` | Kết hợp KG concepts + vector search → context |
| `generate_node` | `nodes_v2.py` | LLM tạo tutor response với grounded context |
| `tts_node` | `nodes_v2.py` | TTS (bypassed — handled externally by lexi_chat.py) |
| `pronunciation_node` | `nodes_v2.py` | HuBERT phân tích phát âm từ audio |

### 2.4 Conditional Edges (Routing Logic)

```python
# File: ai-service/api/services/graph_cag/edges.py

def route_voice_or_text(state) → "stt_node" | "cache_gate_node":
    # voice + audio bytes → STT first
    # text → cache gate trực tiếp

def check_cache_hit(state) → "cache_hit" | "process":
    # cache_decision in ("reuse", "patch") → hit → END
    # "full" → process → kg_diagnose

def route_after_diagnosis(state) → "retrieve_node" | "ask_clarify_node" | "vietnamese_node":
    # confidence < 0.5 → ask_clarify
    # level A1/A2 + errors → vietnamese
    # otherwise → retrieve

def should_analyze_pronunciation(state) → "pronunciation_node" | "end":
    # voice input with audio → pronunciation
    # text → END trực tiếp
```

### 2.5 GraphCAG State Schema

```python
# File: ai-service/api/services/graph_cag/state.py

class GraphCAGState(TypedDict, total=False):
    # INPUT
    user_input: str
    session_id: str
    user_id: Optional[str]
    input_type: str  # "text" | "voice"
    audio_bytes: Optional[bytes]

    # LEARNER CONTEXT (from Redis)
    learner_profile: LearnerProfile
    conversation_history: List[Dict]

    # KNOWLEDGE GRAPH (from KuzuDB)
    kg_seed_concepts: List[str]
    kg_expanded_nodes: List[KGExpandedNode]
    kg_paths: List[Dict]

    # DIAGNOSIS
    diagnosis_intent: str  # "correct" | "explain" | "practice" | "ask"
    diagnosis_errors: List[DiagnosisError]
    diagnosis_root_causes: List[str]
    diagnosis_confidence: float  # 0.0 - 1.0

    # RETRIEVAL
    vector_hits: List[VectorHit]
    retrieved_context: str
    retrieval_trace: List[RetrievalTraceItem]

    # RESPONSE
    tutor_response: str
    vietnamese_hint: Optional[str]
    pronunciation_tip: Optional[str]
    strategy: str  # "praise" | "scaffold" | "socratic" | "feedback"

    # SCORES
    fluency_score: float
    grammar_score: float
    vocabulary_level: str
    overall_score: float

    # RAPID CACHE CONTROL
    cache_fingerprint: Optional[CacheFingerprint]
    cache_decision: str  # "reuse" | "patch" | "full"
    cache_layer: str     # "none" | "L0" | "L1"
    reuse_risk: float    # ρ ∈ [0,1]
```

### 2.6 RAPID Cache System (Paper-Inspired)

Cache 2 tầng theo paper §4.1:
- **L0 Cache**: Query normalization-based, key = (query_norm, intent, level, root_concepts, turn)
- **L1 Cache**: Graph-bucket cache, bucket = concept-state identifier
- **Decisions**: `reuse` (full cache hit) | `patch` (partial update) | `full` (compute từ đầu)
- **Invalidation**: Version tuple `⟨ν_graph, ν_policy, ν_profile, t_refresh⟩`

---

## 3. Model Gateway — Quản Lý Vòng Đời Model

### 3.1 Architecture

```
File: ai-service/api/services/model_gateway.py

ModelGateway
├── Registry        → {name: ModelInfo} dict
├── Loader          → Lazy loading với asyncio.Lock
├── Auto-unload     → Background scheduler (mỗi 60s check idle)
├── Smart Router    → routing_table: task_type → model_name
└── Health Monitor  → psutil memory tracking
```

### 3.2 Model Registry

| Model Name | Type | Memory | Priority | Use Case |
|-----------|------|--------|----------|----------|
| `qwen` | chat | ~4GB | HIGH | Grammar analysis, chat |
| `whisper` | stt | ~1.5GB | NORMAL | Speech-to-text |
| `piper` | tts | ~100MB | NORMAL | Text-to-speech |
| `hubert` | pronunciation | ~2GB | NORMAL | Phoneme analysis |
| `minilm` | embedding | ~90MB | NORMAL | Semantic search |
| `llama_vi` | vietnamese | ~4GB | LOW | Vietnamese explanation |

### 3.3 Lifecycle

```
Unloaded → Loading → Ready → Busy → Ready
                  ↓
               Error
                  ↓  (after idle_timeout_seconds)
              Unloading → Unloaded
```

### 3.4 Memory Management

```python
max_memory_mb = 8000  # 8GB default (env: MAX_MEMORY_MB)

# Khi load model mới:
current_memory + new_model_memory > max_memory_mb
→ _free_memory(needed_mb)
  → unload NORMAL/LOW models theo priority + last_used
```

### 3.5 Task Routing Table

```python
routing_table = {
    "chat"       → "qwen",
    "grammar"    → "qwen",
    "stt"        → "whisper",
    "tts"        → "piper",
    "pronunciation" → "hubert",
    "embed"      → "minilm",
    "translate_vi" → "qwen",  # llama_vi not registered by default
}
```

---

## 4. Smart Router — Định Tuyến Model

### 4.1 Phân Tích Độ Phức Tạp

```
File: ai-service/api/services/smart_router.py

analyze_complexity(text) → {
    "word_count": int,
    "is_simple": word_count < 10,
    "is_greeting": word_count <= 5 AND có "hi/hello/hey/thanks/bye",
    "is_grammar": có keywords "correct/mistake/wrong/error/grammar",
    "has_technical": có "grammar/tense/clause/syntax",
}
```

### 4.2 Routing Rules

```
Rule 1: is_greeting          → local_fast  (gemma2:2b,  ~3s)
Rule 2: is_grammar || "grammar" task → cloud  (Gemini,      ~2s)
Rule 3: word_count > 50      → cloud  (Gemini,      ~2s)
Rule 4: has_technical        → cloud  (Gemini,      ~2s)
Rule 5: is_simple            → local_fast  (gemma2:2b,  ~3s)
Default:                     → cloud  (Gemini,      ~2s)

Hybrid mode OFF (default):   → cloud  (Gemini,      ~2s) [mọi trường hợp]
```

### 4.3 Multi-Provider Fallback Chain

```
OpenRouter → Gemini → Ollama (Local Qwen)
```

---

## 5. Voice Pipeline — Dual-Stream Real-Time

### 5.1 WebSocket Streaming

```
File: ai-service/api/routes/websocket_stream.py

Client WebSocket
    ├── Audio chunks → STT (Whisper streaming)
    ├── Partial transcript → GraphCAG thinking
    └── Response chunks → TTS (chunked) → Audio stream
```

### 5.2 Dual-Stream Architecture

```
[LISTENING Stream]   → [THINKING Stream]   → [SPEAKING Stream]
• VAD                  • GraphCAG               • Chunked TTS
• STT                  • LLM                    • Audio streaming
• Partial transcripts  • Thinking buffer         
        │                                              │
        └──────── INTERRUPTION HANDLING ───────────────┘
                  (user ngắt → TTS stop)
```

### 5.3 Capabilities
- **Voice Activity Detection (VAD)**: Detect khi user bắt đầu/dừng nói
- **Streaming STT**: Real-time speech-to-text với partial transcripts
- **Thinking Buffer**: Merge rapid utterances với pause/merge windows
- **Interruption Handling**: User có thể cắt AI mid-sentence
- **Chunked TTS**: TTS từng đoạn nhỏ để giảm perceived latency

---

## 6. Knowledge Graph Service (KuzuDB)

```
File: ai-service/api/services/kg_service_v3.py  (65KB — file lớn nhất)
```

### 6.1 Cấu Trúc KG

- **Grammar Concepts**: A1→C2, theo CEFR level
- **Vocabulary Domains**: Topic-based (business, travel, etc.)
- **Pronunciation Patterns**: Vietnamese-specific error patterns
- **Prerequisite Chains**: "Past Simple → Past Perfect → Reported Speech"
- **Mastery Tracking**: per-user mastery scores sau mỗi interaction

### 6.2 JIT Graph Service

```
File: ai-service/api/services/jit_graph_service.py

Just-In-Time graph construction:
- Xây dựng subgraph nhỏ (compact) theo context hiện tại
- Tránh load toàn bộ KG vào memory
- Output: "jit_soft_graph" string cho LLM prompt
```

### 6.3 Subgraph Hot Cache

```
File: ai-service/api/services/subgraph_hot_cache.py

- Pre-cache các subgraph phổ biến
- Cung cấp kg_seed_concepts cho GraphCAG (bỏ qua KG lookup)
- TTL-based invalidation
```

---

## 7. HuBERT Pronunciation Analysis

```
File: ai-service/api/services/hubert_service.py
```

### 7.1 Process

```
Audio (WAV, 16kHz) 
    → HuBERT-large (Facebook)
    → IPA phoneme recognition
    → Compare với target pronunciation
    → Per-phoneme confidence scoring
    → Vietnamese-specific error detection
    → Improvement suggestions
```

### 7.2 Vietnamese Error Patterns

| Phoneme | Vietnamese Error | Example |
|---------|----------------|---------|
| θ (think) | → t | "tink" |
| ʃ (shoe) | → s | "sue" |
| ð (this) | → d | "dis" |
| v (very) | → b | "bery" |

### 7.3 Lazy Loading

Model (~2GB) chỉ load khi có audio request đầu tiên. Integrated với Model Gateway cho automatic memory management.

---

## 8. Assessment Service & AI Analytics

### 8.1 Assessment Service

```
File: ai-service/api/services/assessment_service.py

- Full CEFR assessment qua LLM
- Multi-dimensional scoring
- Confidence scoring
- Trend analysis
```

### 8.2 AI Audit Route

```
File: backend-service/app/routes/ai_audit.py

- Log AI decisions với context
- Audit trail cho mọi AI interaction
- Phục vụ transparency và debugging
```

---

## 9. Các Service AI Phụ Trợ

| Service | File | Chức năng |
|---------|------|-----------|
| `EmbeddingService` | `embedding_service_v3.py` | Sentence embeddings cho semantic search |
| `VectorStoreService` | `vector_store_service.py` | Vector similarity search |
| `RetrievalService` | `retrieval_service_v3.py` | Kết hợp KG + vector retrieval |
| `ReportService` | `report_service.py` | Tạo báo cáo học tập tổng hợp |
| `SpacedRepetitionService` | `spaced_repetition_service.py` | SM-2 scheduling |
| `StoryService` | `story_service.py` | Tạo câu chuyện học tập |
| `TopicCatalogService` | `topic_catalog_service.py` | Danh mục chủ đề chat |
| `TopicLLMGateway` | `topic_llm_gateway.py` | LLM gateway cho topic chat |
| `TopicPromptBuilder` | `topic_prompt_builder.py` | Xây dựng prompt theo chủ đề |
| `DLModelService` | `dl_model_service.py` | Fine-tuned Qwen model service |
| `QwenEngine` | `qwen_engine.py` | Qwen model inference engine |
| `FallbackService` | `fallback.py` | Fallback khi primary service fail |
| `LoggingService` | `logging_service.py` | Structured logging |
| `Metrics` | `metrics.py` | Performance metrics collection |
| `Telemetry` | `telemetry.py` | OpenTelemetry tracing |
| `PerformanceMonitor` | `performance_monitor.py` | Realtime performance tracking |
| `ResourceManager` | `resource_manager.py` | System resource monitoring |

---

## 10. AI Service API Endpoints

| Prefix | Router File | Chức năng |
|--------|------------|-----------|
| `/api/v1/chat` | `chat.py` | Chat sessions cơ bản |
| `/api/v1/stt` | `stt.py` | Speech-to-text |
| `/api/v1/tts` | `tts.py` | Text-to-speech |
| `/api/v1/topics` | `topic_chat.py` | Topic-based chat |
| `/api/v1/admin` | `admin.py` | Admin operations |
| `/api/v1/ai` | `ai.py` | AI analytics |
| `/api/v1/lexi*` | `lexi_chat.py` | Lexi Chat (GraphCAG) |
| `/warmup` | `main.py` | Model preload trigger |
| `/visualizer` | `main.py` | GraphCAG node visualizer |

---

## 11. MongoDB Collections (AI Service)

| Collection | Mục đích |
|-----------|---------|
| `chat_sessions` | Phiên chat thông thường |
| `chat_messages` | Messages trong phiên chat |
| `lexi_sessions` | Phiên Lexi Chat nâng cao |
| `lexi_messages` | Messages Lexi Chat |

**Indexes:**
- `chat_sessions.session_id` (unique)
- `chat_sessions(user_id, last_activity)` (composite)
- `chat_messages(session_id, timestamp)` (composite)
- `lexi_sessions.session_id` (unique)
- `lexi_messages(session_id, timestamp)` (composite)

---

*Tham khảo: [RPT-018](RPT-018_FEATURE_ANALYSIS.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md) | [RPT-021](RPT-021_GRAPHCAG_ALGORITHM_FLOW.md)*
