# RPT-023 — Technology Stack & Special Tools Analysis

> **Cập nhật:** 2026-04-24 | Tổng hợp toàn bộ công nghệ và tools đặc biệt trong LexiLingo

---

## 1. Technology Stack Tổng Quan

```
┌─────────────────────────────────────────────────────────────┐
│                    CLIENT LAYER                              │
│          Flutter 3.24+ (iOS / Android / Web)                │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                   API GATEWAY LAYER                          │
│        Kong / Nginx / Cloudflare (Load Balancing)           │
└──────────┬──────────────────────┬───────────────────────────┘
           │                      │
┌──────────▼─────────┐  ┌────────▼──────────────────────────┐
│  BACKEND SERVICE   │  │         AI SERVICE                 │
│  FastAPI + PG +    │  │  FastAPI + MongoDB + Redis +        │
│  Redis + Firebase  │  │  LangGraph + KuzuDB + PyTorch       │
└──────────┬─────────┘  └────────┬──────────────────────────┘
           │                      │
           └──────────┬───────────┘
                      │
         ┌────────────▼────────────┐
         │    DATA LAYER           │
         │  PostgreSQL  │  MongoDB  │
         │  Redis       │  KuzuDB   │
         └─────────────────────────┘
```

---

## 2. AI & Machine Learning Stack

### 2.1 Core AI Tools (Đặc Biệt)

#### 🔷 LangGraph (Orchestration)

| Attribute | Value |
|-----------|-------|
| **Package** | `langgraph >= 0.0.66` |
| **Role** | Stateful multi-step AI pipeline orchestration |
| **Pattern** | StateGraph + conditional edges |
| **State** | `TRACECAGState` (TypedDict, 40+ fields) |
| **Use Case** | TRACECAG pipeline (8 nodes, 6 edges) |

**Tại sao LangGraph?**
- Native async support → `ainvoke()`, `astream()`
- Conditional routing built-in
- Stateful memory giữa các nodes
- Kiểm soát flow phức tạp (cache hit, voice/text path chia đôi)

#### 🔷 KuzuDB (Knowledge Graph)

| Attribute | Value |
|-----------|-------|
| **Package** | `kuzu >= 0.4.2` |
| **Role** | Embedded graph database cho curriculum |
| **Pattern** | Property graph với Cypher-like queries |
| **File** | `ai-service/api/services/kg_service_v3.py` (65KB) |

**Schema KG:**
```cypher
// Node types
CREATE NODE TABLE Concept(id STRING PRIMARY KEY, title STRING, level STRING, ...)
CREATE NODE TABLE User(id STRING PRIMARY KEY, ...)
CREATE NODE TABLE Session(id STRING PRIMARY KEY, ...)

// Edge types
CREATE REL TABLE PREREQUISITE(FROM Concept TO Concept)
CREATE REL TABLE RELATED(FROM Concept TO Concept)
CREATE REL TABLE MASTERY(FROM User TO Concept, score FLOAT)
CREATE REL TABLE PRACTICED(FROM User TO Concept, session_id STRING)
```

**Graph Queries:**
```cypher
// Find concepts related to user input
MATCH (c:Concept)-[:RELATED*1..2]-(neighbor)
WHERE c.keywords CONTAINS $keyword
RETURN c, neighbor LIMIT 10

// Check mastery
MATCH (u:User {id: $uid})-[m:MASTERY]->(c:Concept)
WHERE m.score < 0.7
RETURN c.id, m.score ORDER BY m.score
```

#### 🔷 HuBERT-large (Pronunciation)

| Attribute | Value |
|-----------|-------|
| **Model** | `facebook/hubert-large-ls960-ft` |
| **Package** | `transformers >= 4.37.0, < 6.0.0` |
| **RAM** | ~2GB |
| **Input** | Audio WAV 16kHz |
| **Output** | Phoneme sequences + confidence scores |
| **File** | `ai-service/api/services/hubert_service.py` |

**Pipeline:**
```python
# Lazy load via ModelGateway
processor = Wav2Vec2Processor.from_pretrained("facebook/hubert-large-ls960-ft")
model = HubertForCTC.from_pretrained("facebook/hubert-large-ls960-ft")

# Inference
inputs = processor(audio, sampling_rate=16000, return_tensors="pt")
logits = model(**inputs).logits
predicted_ids = torch.argmax(logits, dim=-1)
transcription = processor.batch_decode(predicted_ids)
```

#### 🔷 Qwen3 + LoRA (Custom Fine-tuned)

| Attribute | Value |
|-----------|-------|
| **Base** | Qwen3-1.7B |
| **Fine-tune** | LoRA (PEFT framework) |
| **Package** | `peft >= 0.8.0`, `torch >= 2.2.0` |
| **Use** | ESL grammar analysis, Vietnamese explanation |
| **File** | `ai-service/api/services/qwen_engine.py` |
| **Modelfile** | `ai-service/Modelfile.qwen3-1.7b` (cho Ollama) |

**LoRA Config:**
```python
# Fine-tuning target: grammar_check, error_detection tasks
# Training: ai-service/model-development/notebook/
config = LoraConfig(
    r=16, lora_alpha=32,
    target_modules=["q_proj", "v_proj"],
    lora_dropout=0.05,
    task_type="CAUSAL_LM"
)
```

#### 🔷 faster-whisper (STT)

| Attribute | Value |
|-----------|-------|
| **Package** | `faster-whisper >= 1.1.0` |
| **Model** | Whisper (medium or large-v3) |
| **Backend** | CTranslate2 (4x faster than original) |
| **File** | `ai-service/api/services/stt_service.py` |
| **Route** | `ai-service/api/routes/stt.py` |

#### 🔷 Piper TTS + gTTS

| Attribute | Value |
|-----------|-------|
| **Piper** | `piper-tts >= 1.2.0` — Low-latency local TTS |
| **gTTS** | `gTTS >= 2.5.0` — Google TTS fallback |
| **Note** | TTS handled externally by lexi_chat.py (không trong TRACECAG) |
| **File** | `ai-service/api/services/tts_service.py` |

#### 🔷 sentence-transformers (Embeddings)

| Attribute | Value |
|-----------|-------|
| **Package** | `sentence-transformers >= 2.2.2, < 6.0.0` |
| **Model** | MiniLM (all-MiniLM-L6-v2) |
| **RAM** | ~90MB |
| **File** | `ai-service/api/services/embedding_service_v3.py` |
| **Use** | Vector search, semantic similarity |

#### 🔷 GLiNER (Named Entity Recognition)

| Attribute | Value |
|-----------|-------|
| **Package** | `gliner >= 0.2.14` |
| **Use** | Extract entities từ user text |
| **Benefit** | Identify grammar concepts, keywords |

#### 🔷 llama-cpp-python (Vietnamese Explanation)

| Attribute | Value |
|-----------|-------|
| **Package** | `llama-cpp-python >= 0.2.50` |
| **Use** | GGUF model inference cho Vietnamese |
| **File** | `ai-service/api/services/llama_vietnamese_service.py` |
| **Note** | Không active trong routing table hiện tại (fallback về qwen) |

---

### 2.2 LLM Providers

| Provider | Package/API | Model | Use Case |
|---------|------------|-------|---------|
| **Google Gemini** | `google-generativeai >= 0.3.0` | gemini-2.0-flash | Primary cloud LLM |
| **Groq** | httpx (REST) | qwen3-32b (via Groq cloud) | Fast cloud inference |
| **Ollama** | `OllamaService` (local HTTP) | gemma2:2b, qwen3:4b | Local inference |
| **OpenRouter** | httpx (REST) | Multi-model | Fallback provider |

**Fallback Chain:** `OpenRouter → Gemini → Ollama`

---

## 3. Backend Stack

### 3.1 Core Framework

| Technology | Version | Role |
|-----------|---------|------|
| **FastAPI** | >= 0.109.0 | Async REST API framework |
| **Uvicorn** | >= 0.27.0 | ASGI server |
| **Python** | 3.11+ | Runtime |

### 3.2 Database Layer

| Technology | Version | Role |
|-----------|---------|------|
| **PostgreSQL** | 14+ | Primary relational DB |
| **SQLAlchemy** | >= 2.0.25 (async) | ORM |
| **asyncpg** | >= 0.29.0 | Async PostgreSQL driver |
| **aiosqlite** | >= 0.19.0 | SQLite driver (dev/test) |
| **Alembic** | >= 1.13.1 | Schema migrations |
| **Pydantic** | >= 2.5.0 | Data validation |
| **pydantic-settings** | >= 2.1.0 | Config management |

### 3.3 Auth & Security

| Technology | Role |
|-----------|------|
| **python-jose** | JWT encode/decode |
| **passlib + bcrypt** | Password hashing |
| **firebase-admin** | Firebase ID token verification |
| **google-auth** | Google OAuth |

### 3.4 Caching & Rate Limiting

| Technology | Version | Role |
|-----------|---------|------|
| **Redis** | >= 4.5.0 | Cache, rate limiting, token blacklist |
| **redis-py** | async client | Python Redis client |

### 3.5 Content Parsing

| Technology | Role |
|-----------|------|
| **feedparser >= 6.0.0** | RSS feed parsing (podcasts) |
| **trafilatura >= 1.6.0** | News article full-text extraction |

---

## 4. AI Service Infrastructure

### 4.1 Database

| Technology | Version | Role |
|-----------|---------|------|
| **MongoDB** | cloud/local | Chat sessions, AI conversation history |
| **Motor** | >= 3.6.0, < 3.8.0 | Async MongoDB driver |
| **PyMongo** | >= 4.9.2 | Sync operations |
| **Redis** | >= 5.0.1 | Rate limiting, session cache, CAG |

### 4.2 Data Science

| Technology | Version | Role |
|-----------|---------|------|
| **numpy** | >= 1.23.0, < 3.0.0 | Numerical operations |
| **scipy** | >= 1.11.0 | Audio resampling |
| **networkx** | == 3.6.1 | Graph algorithm utilities |
| **torch** | >= 2.2.0, <= 2.11.0 | Deep learning (HuBERT, Qwen) |
| **accelerate** | >= 0.25.0 | Training/inference acceleration |

### 4.3 Monitoring & Observability

| Technology | Role |
|-----------|------|
| **psutil** | System resource monitoring |
| **loguru** | Structured logging |
| **OpenTelemetry** | Distributed tracing (telemetry.py) |
| **Prometheus** | Metrics (metrics.py) |

---

## 5. Flutter Dependencies (Đặc Biệt)

### 5.1 Audio Engineering

| Package | Version | Role |
|---------|---------|------|
| `record` | ^5.2.1 | Audio recording (mic input) |
| `just_audio` | ^0.9.46 | Audio playback |
| `audio_service` | ^0.18.16 | Background audio, lock screen controls |
| `record_linux` | 1.3.0 (override) | Linux audio fix |
| `record_web` | ^1.3.0 (override) | Web audio fix |

### 5.2 Special Packages

| Package | Version | Role |
|---------|---------|------|
| `dartz` | ^0.10.1 | Functional programming (Either, Option) |
| `equatable` | ^2.0.5 | Value equality cho entities |
| `sqflite` | ^2.4.2 | Local SQLite database |
| `sqflite_common_ffi_web` | ^1.1.1 | SQLite Web support |
| `easy_localization` | ^3.0.7 | i18n with JSON files |
| `flutter_dotenv` | ^6.0.0 | .env file loading |
| `encrypt` | ^5.0.3 | Data encryption |
| `geolocator` | ^13.0.1 | Location (level/achievement features) |
| `web_socket_channel` | (transitive) | WebSocket cho voice streaming |

---

## 6. Gateway & Infrastructure

### 6.1 API Gateway

| Technology | Config File | Role |
|-----------|------------|------|
| **Kong** | `gateway/kong/` | Main API Gateway, plugin chain |
| **Nginx** | `gateway/nginx/` | Reverse proxy, SSL termination |
| **Cloudflare** | `gateway/cloudflare/` | DNS + CDN + DDOS protection |

**Kong Plugins:**
- Rate limiting
- CORS handling
- JWT validation
- IP restriction
- Request transformation
- Response transformation

### 6.2 Observability Stack

```
gateway/observability/
├── Prometheus    → Metrics collection
├── Grafana       → Metrics visualization
└── Jaeger/Tempo  → Distributed tracing
```

### 6.3 Deployment Infrastructure

| Tool | Role |
|------|------|
| **Docker Compose** | Multi-service orchestration |
| **Render.com** | Backend cloud deployment |
| **Vercel** | Flutter Web + Admin frontend |
| **VPS + Nginx + SSL** | Self-hosted option |
| **systemd** | Linux service management |
| **fail2ban** | Security hardening |

---

## 7. Development Tooling

### 7.1 Backend

| Tool | Version | Role |
|------|---------|------|
| **black** | >= 23.12.1 | Code formatting |
| **isort** | >= 5.13.2 | Import sorting |
| **flake8** | >= 7.0.0 | Linting |
| **mypy** | >= 1.8.0 | Type checking (AI service) |
| **pytest** | >= 8.2.0 | Testing framework |
| **pytest-asyncio** | >= 0.24.0 | Async test support |

### 7.2 Git & CI/CD

```
.pre-commit-config.yaml → Pre-commit hooks
.github/               → GitHub Actions workflows
.pr_agent.toml         → PR Agent configuration
```

### 7.3 Flutter

| Tool | Role |
|------|------|
| `flutter_lints ^5.0.0` | Lint rules |
| `flutter_test` | Testing |
| `mockito ^5.4.4` | Mocking |
| `build_runner ^2.4.13` | Code generation |
| `flutter_launcher_icons` | App icon generation |
| `crowdin.yml` | Translation management |

---

## 8. Đặc Biệt: Các Tool Tự Phát Triển

### 8.1 TRACECAG Node Visualizer

```
Route: GET /visualizer
Redirect: /static/TRACECAG-node-viz.html
Location: ai-service/static/TRACECAG-node-viz.html

Purpose: Visual tool để debug TRACECAG pipeline execution
- Hiển thị nodes và edges
- Trace pipeline execution path
- Hover để xem state tại mỗi node
```

### 8.2 RAPID Cache System

```
Location: ai-service/api/services/ (embedded in graph_cag)

Custom cache algorithm theo paper:
- L0: Fingerprint-based exact match
- L1: Graph-bucket semantic match
- Adaptive risk scoring (ρ)
- Version-based invalidation
```

### 8.3 JIT Graph Service

```
File: ai-service/api/services/jit_graph_service.py (12KB)

Just-In-Time graph construction:
- Tạo compact subgraph string cho LLM prompt
- Avoid loading full KG vào memory
- Context-aware graph slicing
```

### 8.4 Topic Preloader

```
File: ai-service/api/services/topic_preloader.py (4KB)

Pre-load popular topic contexts:
- Warm cache cho top topics
- Reduce first-message latency
- Background task on startup
```

### 8.5 Document Intelligence

```
File: ai-service/api/services/document_intelligence.py (6KB)

Intelligent document processing:
- Extract structured info từ text
- Identify learning-relevant content
- News/book content analysis
```

### 8.6 Evaluation Agent

```
File: ai-service/api/services/graph_cag/evaluation_agent.py (12KB)

Automatic quality evaluation:
- WER, TTR, Error Density
- Precision@K, Recall@K, NDCG@K, MRR
- Composite score computation
- Grammar/fluency scoring
```

### 8.7 Retrieval Ranker

```
File: ai-service/api/services/graph_cag/retrieval_ranker.py (6KB)

Advanced retrieval ranking:
- Multi-factor score fusion
- KG relevance + Vector similarity
- Diversity re-ranking
```

---

## 9. Algorithms & Data Structures

| Algorithm | Implementation | File |
|---------|--------------|------|
| **SM-2 Spaced Repetition** | EF calculation, interval progression | `spaced_repetition_service.py` |
| **EMA Skill Scoring** | Exponential Moving Average cho proficiency | `proficiency_service.py` |
| **CEFR Assessment** | Multi-dimensional weighted scoring | `proficiency_service.py` |
| **RAPID Cache** | 2-level cache với risk scoring | `graph_cag/state.py` + nodes |
| **SmartRouter** | Complexity heuristics cho model routing | `smart_router.py` |
| **Graph Hop Expansion** | BFS/DFS trên KuzuDB | `kg_service_v3.py` |
| **Vector Similarity** | Cosine similarity (sentence-transformers) | `embedding_service_v3.py` |
| **NDCG@K** | Normalized Discounted Cumulative Gain | `evaluation_agent.py` |
| **MRR** | Mean Reciprocal Rank | `evaluation_agent.py` |
| **WER** | Word Error Rate | `evaluation_agent.py` |

---

## 10. Port Map

| Service | Port | Protocol |
|---------|------|---------|
| Backend Service | 8000 | HTTP |
| AI Service | 8001 | HTTP + WebSocket |
| Flutter Web | 8080 | HTTP |
| Admin Service | 5173 (dev) | HTTP |
| PostgreSQL | 5432 | PostgreSQL |
| MongoDB | 27017 | MongoDB |
| Redis | 6379 | Redis |
| Ollama | 11434 | HTTP |
| Kong Gateway | 8080/8443 | HTTP/HTTPS |
| Nginx | 80/443 | HTTP/HTTPS |

---

## 11. Environment Configuration

### 11.1 Backend (.env)

```bash
# App
APP_NAME=LexiLingo Backend
APP_ENV=development|production
DEBUG=true|false
PORT=8000

# Database
DATABASE_URL=postgresql+asyncpg://user:pass@host/db
SQLITE_URL=sqlite+aiosqlite:///./lexilingo.db  # dev only

# Redis
REDIS_URL=redis://localhost:6379

# Auth
SECRET_KEY=xxx
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30

# Firebase
FIREBASE_PROJECT_ID=lexilingo-88492

# AI Service
AI_SERVICE_URL=http://localhost:8001

# CORS
CORS_ORIGINS=["http://localhost:3000", "https://lexilingo.me"]
```

### 11.2 AI Service (.env)

```bash
# Providers
GEMINI_API_KEY=xxx
GROQ_API_KEY=xxx
GROQ_MODEL=qwen/qwen3-32b
OLLAMA_BASE_URL=http://localhost:11434
OLLAMA_MODEL=lexilingo-qwen3-1.7b

# MongoDB
MONGODB_URI=mongodb://localhost:27017
MONGODB_DATABASE=lexilingo_ai

# Redis
REDIS_URL=redis://localhost:6379

# Model Gateway
MAX_MEMORY_MB=8000
USE_GATEWAY=true
HYBRID_MODE=false
COMPLEXITY_THRESHOLD=50

# KuzuDB
KUZU_DB_PATH=./data/kuzu_db
```

### 11.3 Flutter (.env)

```bash
BACKEND_URL=http://localhost:8000
AI_SERVICE_URL=http://localhost:8001
GOOGLE_CLIENT_ID=xxx
```

---

*Tham khảo: [RPT-018](RPT-018_FEATURE_ANALYSIS.md) | [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-020](RPT-020_BACKEND_SERVICE_REPORT.md)*
