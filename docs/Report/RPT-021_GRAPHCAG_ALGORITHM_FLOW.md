# RPT-021 — TRACECAG Algorithm Flow: Phân Tích Chi Tiết Thuật Toán

> **Cập nhật:** 2026-04-24 | **Pipeline Version:** TRACECAG v3 với RAPID Cache

---

## 1. Giới Thiệu TRACECAG

**TRACECAG = Graph-augmented Cache-Augmented Generation**

Đây là thuật toán AI cốt lõi của LexiLingo, kết hợp:

| Thành phần | Vai trò | Công nghệ |
|-----------|---------|-----------|
| **Graph** | Knowledge Graph structured knowledge | KuzuDB |
| **CAG** | Cache-Augmented Generation (không phải RAG) | Redis L0/L1 |
| **LangGraph** | Orchestration StateGraph | langgraph ≥ 0.0.66 |
| **LLM** | Language model cho reasoning | Gemini / Ollama Qwen |

### Tại sao CAG, không phải RAG?

| RAG (Retrieval-Augmented Generation) | CAG (Cache-Augmented Generation) |
|-------------------------------------|----------------------------------|
| Tìm kiếm document từ vector store | Cache learner context từ Redis |
| Phụ thuộc document quality | Phụ thuộc cache freshness |
| Latency cao (embedding + search) | Latency thấp (cache hit < 1ms) |
| Không có learner personalization | Personalized theo từng người học |

---

## 2. TRACECAG State — Trung Tâm Dữ Liệu

```python
# File: ai-service/api/services/graph_cag/state.py

TRACECAGState (TypedDict):
    # === INPUT (set at start) ===
    user_input: str              # "I goes to school yesterday"
    session_id: str              # UUID cho phiên
    user_id: Optional[str]       # Để load profile
    input_type: "text" | "voice"
    audio_bytes: bytes           # Raw audio nếu voice

    # === LEARNER CONTEXT (Redis CAG) ===
    learner_profile:             # level, native_language, common_errors
    conversation_history: List   # Lịch sử turns

    # === KNOWLEDGE GRAPH (KuzuDB) ===
    kg_seed_concepts: List[str]  # ["past_simple", "irregular_verbs"]
    kg_expanded_nodes: List      # Nodes expand from graph hops
    kg_paths: List               # Paths giữa concepts

    # === DIAGNOSIS ===
    diagnosis_intent: str        # "correct" | "explain" | "practice" | "ask"
    diagnosis_errors: List       # [{span, type, correction, explanation}]
    diagnosis_root_causes: List  # Concept IDs gốc lỗi
    diagnosis_confidence: float  # 0.0 → 1.0

    # === RETRIEVAL ===
    vector_hits: List[VectorHit]
    jit_soft_graph: str          # Compact JIT graph string cho LLM
    retrieved_context: str       # Final combined context
    retrieval_trace: List        # Cho đánh giá retrieval quality

    # === RESPONSE ===
    tutor_response: str
    vietnamese_hint: Optional[str]
    pronunciation_tip: Optional[str]
    strategy: "praise"|"scaffold"|"socratic"|"feedback"

    # === SCORES ===
    fluency_score: float
    grammar_score: float
    vocabulary_level: str
    overall_score: float

    # === RAPID CACHE CONTROL ===
    cache_fingerprint: CacheFingerprint
    cache_decision: "reuse"|"patch"|"full"
    cache_layer: "none"|"L0"|"L1"
    cache_bucket: str            # Graph-aware bucket ID
    reuse_risk: float            # ρ ∈ [0,1]

    # === METADATA ===
    models_used: List[str]       # Accumulator
    latency_ms: int
    cache_hit: bool
    path: "fast"|"slow"
    tokens_saved: int
```

---

## 3. Algorithm Flow — Toàn Bộ Pipeline

### 3.1 Entry Point

```python
# Caller: lexi_chat.py → TRACECAGPipeline.analyze()

pipeline = await get_graph_cag()
result = await pipeline.analyze(
    user_input = "I goes to school yesterday",
    session_id = "sess_abc123",
    user_id    = "user_xyz",
    input_type = "text",
    cache_policy    = "on",   # "on" | "off"
    retrieval_policy = "full", # "full" | "rapid"
    diagnosis_policy = "auto", # "auto" | "rules"
    generation_policy= "auto", # "auto" | "extractive"
)
```

### 3.2 StateGraph Compilation

```python
# File: graph.py

graph = StateGraph(TRACECAGState)

# Nodes
graph.add_node("input_node",        input_node)
graph.add_node("cache_gate_node",   cache_gate_node)
graph.add_node("kg_expand_node",    kg_expand_node)
graph.add_node("diagnose_node",     diagnose_node)
graph.add_node("kg_diagnose_node",  kg_diagnose_node)  # parallel wrapper
graph.add_node("retrieve_node",     retrieve_node)
graph.add_node("generate_node",     generate_node)
graph.add_node("vietnamese_node",   vietnamese_node)
graph.add_node("ask_clarify_node",  ask_clarify_node)
graph.add_node("stt_node",          stt_node)
graph.add_node("pronunciation_node",pronunciation_node)
graph.add_node("tts_node",          tts_node)          # unregistered but exists

graph.set_entry_point("input_node")

# Compiled as singleton
compiled_graph = graph.compile()
```

---

## 4. Node-by-Node Algorithm Detail

### Node 1: `input_node`

**Mục đích:** Load learner context từ Redis, khởi tạo state

```
Algorithm:
1. Nhận user_input, session_id, user_id
2. Load learner_profile từ Redis (key: "profile:{user_id}")
   → Nếu không có: dùng default {"level": "B1"}
3. Load conversation_history từ Redis (key: "history:{session_id}")
4. Update state.learner_profile, state.conversation_history
5. Normalize user_input (lowercase, strip whitespace)
```

**Output state updates:**
- `learner_profile` populated
- `conversation_history` populated

**Edge → `route_voice_or_text`:**
- voice + audio_bytes → `stt_node`
- text → `cache_gate_node`

---

### Node 2: `stt_node` (voice path only)

**Mục đích:** Chuyển audio → text

```
Algorithm:
1. Lấy audio_bytes từ state
2. Gọi Whisper (faster-whisper) với audio
3. Nhận transcript text
4. Store vào state.user_input (override)
```

**Edge →** `cache_gate_node`

---

### Node 3: `cache_gate_node` (RAPID Cache)

**Mục đích:** Kiểm tra cache hit theo thuật toán RAPID (paper §4.1)

```
Algorithm (3-level decision):

Step 1: Tạo CacheFingerprint:
    fingerprint = {
        query_norm:    normalize(user_input),
        intent:        state.diagnosis_intent,
        level:         learner_profile.level,
        root_concepts: state.diagnosis_root_causes,
        session_turn:  len(conversation_history),
    }

Step 2: L0 Cache Check (exact fingerprint lookup):
    key = hash(fingerprint)
    cached = redis.get("cache_L0:{key}")
    IF cached:
        → cache_decision = "reuse" (or "patch")
        → Populate tutor_response từ cache
        → cache_layer = "L0"
        RETURN

Step 3: L1 Cache Check (graph-bucket lookup):
    bucket = compute_graph_bucket(kg_seed_concepts, level)
    version = redis.get("bucket_version:{bucket}")
    IF version valid:
        → cache_decision = "reuse" (or "patch")
        → cache_layer = "L1"
        RETURN

Step 4: Cache miss
    → cache_decision = "full"
    → cache_layer = "none"
```

**Reuse Risk (ρ):**
```
reuse_risk ρ ∈ [0,1]:
- Tính dựa trên: concept staleness, profile drift, turn distance
- ρ > threshold → force "full" (không dùng cache dù có)
```

**Edge → `check_cache_hit`:**
- `cache_decision in ("reuse", "patch")` → `END` (trả về từ cache)
- `"full"` → `kg_diagnose_node`

---

### Node 4: `kg_diagnose_node` (Parallel Execution)

**Mục đích:** Chạy KG expand + Diagnose song song

```python
# asyncio.gather: 2 tác vụ song song
await asyncio.gather(
    kg_expand_node(state),
    diagnose_node(state),
)
```

---

### Node 4a: `kg_expand_node` (Knowledge Graph)

**Mục đích:** Tìm concepts liên quan trong KuzuDB

```
Algorithm:
1. Extract keywords từ user_input
   → "I goes to school yesterday" → ["goes", "yesterday", "past"]

2. Match keywords → KG concepts (KuzuDB lookup)
   → ["past_simple", "irregular_verbs", "time_expressions"]
   → Store as kg_seed_concepts

3. Graph hop expansion (depth=2):
   past_simple
   ├── PREREQUISITE: simple_present
   ├── PREREQUISITE_OF: past_perfect
   ├── RELATED: time_expressions
   └── ERROR_PATTERN: third_person_singular

4. Collect expanded nodes, paths
   → Store kg_expanded_nodes, kg_paths

5. Update mastery scores:
   → Fetch per-user mastery từ Redis/DB
   → Filter concepts theo mastery gap (học trước những cái chưa master)
```

**Output:**
- `kg_seed_concepts`: ["past_simple", "irregular_verbs"]
- `kg_expanded_nodes`: Full expanded list with titles, relations
- `kg_paths`: Prerequisite chains

---

### Node 4b: `diagnose_node` (AI Grammar Analysis)

**Mục đích:** Phân tích lỗi ngôn ngữ bằng AI

```
Algorithm:
1. Tạo diagnosis prompt:
   "{user_input} [learner: level={level}, native={native_language}]"
   "Identify: intent, grammar errors, fluency issues, confidence"

2. Gọi AI model (qua ModelGateway → Gemini/Qwen):
   response = await gateway.invoke("qwen", "analyze_grammar", {...})

3. Parse JSON response:
   {
     "intent": "correct",  // "correct" | "explain" | "practice" | "ask"
     "errors": [
       {"span": "goes", "type": "verb_conjugation",
        "correction": "went", "explanation": "Past simple irregular verb"}
     ],
     "root_cause_concepts": ["past_simple", "irregular_verbs"],
     "confidence": 0.92,
     "fluency_score": 0.75,
     "grammar_score": 0.65,
   }

4. Store in state
```

**Output:**
- `diagnosis_intent`: "correct"
- `diagnosis_errors`: [{span, type, correction, explanation}]
- `diagnosis_root_causes`: ["past_simple", "irregular_verbs"]
- `diagnosis_confidence`: 0.92

---

### Edge: `route_after_diagnosis`

```python
def route_after_diagnosis(state):
    confidence = state.get("diagnosis_confidence", 1.0)
    level = state["learner_profile"].get("level", "B1")
    errors = state.get("diagnosis_errors", [])

    if confidence < 0.5:
        return "ask_clarify_node"  # Cần thêm thông tin

    if level in ["A1", "A2"] and len(errors) > 0:
        return "vietnamese_node"   # Giải thích tiếng Việt trước

    return "retrieve_node"         # Normal flow
```

---

### Node 5: `vietnamese_node` (A1/A2 path)

**Mục đích:** Giải thích lỗi bằng tiếng Việt trước khi retrieve

```
Algorithm:
1. Lấy diagnosis_errors từ state
2. Tạo explanation prompt tiếng Việt:
   "Giải thích lỗi '{error}' cho học sinh A1/A2"
3. Gọi AI model (Qwen/LLaMA-Vietnamese)
4. Store vietnamese_hint
```

**Edge →** `retrieve_node` (luôn luôn)

---

### Node 5 (alt): `ask_clarify_node`

**Mục đích:** Hỏi làm rõ khi AI không đủ confidence

```
Algorithm:
1. Tạo clarification question:
   "Bạn muốn tôi: [A] Sửa lỗi, [B] Giải thích, [C] Luyện tập?"
2. Store tutor_response = clarification question
3. KHÔNG gọi retrieve/generate
```

**Edge →** `END` (tutor_response đã có, bỏ qua generate)

---

### Node 6: `retrieve_node`

**Mục đích:** Kết hợp KG context + Vector search

```
Algorithm:
Step 1: KG Context Assembly:
    - Lấy kg_expanded_nodes
    - Lấy jit_soft_graph (từ JIT Graph Service)
    - Format thành structured context string

Step 2: Vector Search (nếu cần thêm context):
    - Embed diagnosis_root_causes + user_input
    - Search vector store (FAISS/ChromaDB)
    - Lấy top-k relevant examples/explanations
    - Store as vector_hits

Step 3: Context Fusion:
    retrieved_context = kg_context + vector_hits + conversation_history

Step 4: Retrieval Ranking (EvaluationAgent):
    - Rank retrieved items theo relevance
    - Store retrieval_trace (cho evaluation)
    - Compute: precision@k, NDCG@k, MRR, recall@k
```

**Output:**
- `retrieved_context`: Grounded context string
- `vector_hits`: Semantic search results
- `retrieval_trace`: Ranked items với scores

---

### Node 7: `generate_node`

**Mục đích:** LLM tạo tutor response

```
Algorithm:
Step 1: Build Generation Prompt:
    system_prompt = f"""
    You are LexiLingo, an English tutor.
    Learner: level={level}, native={native_language}

    Knowledge Graph Context:
    {retrieved_context}

    Strategy: {strategy}  # scaffold | praise | socratic | feedback
    """

    messages = conversation_history + [
        {"role": "user", "content": user_input}
    ]

Step 2: Route to Model:
    - is_grammar query → cloud (Gemini)
    - simple greeting → local_fast (gemma2:2b)
    - complex analysis → cloud (Gemini/qwen3)

Step 3: Generate Response:
    response = await model.generate(system_prompt, messages)

Step 4: Post-process:
    - Extract tutor_response text
    - Extract pronunciation_tip nếu có
    - Update conversation_history
    - Update KG mastery scores (graph_update)

Step 5: Save to Cache (nếu cache_decision == "full"):
    - Tạo CacheEntry với TTL
    - Store L0 và L1 cache entries trong Redis

Step 6: Compute Scores:
    overall_score = EvaluationAgent.compute_overall_score(
        grammar_score, fluency_score, vocabulary_level
    )
```

**Output:**
- `tutor_response`: Final AI tutor response
- `grammar_score`, `fluency_score`, `overall_score`
- `models_used`: List các model đã dùng
- `cache_hit`, `tokens_saved`

---

### Node 8: `pronunciation_node` (voice path only)

**Mục đích:** Phân tích phát âm bằng HuBERT

```
Algorithm:
1. Lấy audio_bytes từ state
2. Resample audio → 16kHz WAV
3. Load HuBERT-large (lazy via ModelGateway)
4. Tokenize → phoneme recognition
5. Compare với target pronunciation
6. Per-phoneme confidence scoring
7. Detect Vietnamese error patterns (θ→t, ʃ→s, ð→d)
8. Generate pronunciation_tip

Output: pronunciation_tip in state
```

**Edge →** `END`

---

## 5. Response Format

```json
{
    "tutor_response": "Great attempt! However, 'went' is the correct past form of 'go'...",
    "corrections": [
        {
            "error": "goes",
            "correction": "went",
            "type": "verb_conjugation",
            "explanation": "Past simple: 'go' is irregular, past = 'went'"
        }
    ],
    "linked_concepts": ["past_simple", "irregular_verbs"],
    "vietnamese_hint": "Động từ 'go' là động từ bất quy tắc...",
    "pronunciation_tip": null,
    "scores": {
        "fluency": 0.75,
        "grammar": 0.65,
        "overall": 0.69,
        "vocabulary_level": "B1",
        "diagnosis_confidence": 0.92,
        "wer": 0.1428,
        "word_count": 7,
        "correction_count": 1,
        "error_density": 0.1428,
        "type_token_ratio": 0.8571,
        "retrieval": {
            "precision_k": 0.8,
            "recall_k": 0.6,
            "ndcg_k": 0.7512,
            "mrr": 0.6667
        }
    },
    "action": {
        "strategy": "scaffold",
        "next": "continue"
    },
    "metadata": {
        "latency_ms": 1250,
        "ttft_ms": 340,
        "models_used": ["gemini-2.0-flash"],
        "path": "slow",
        "cache_hit": false,
        "cache_decision": "full",
        "cache_layer": "none",
        "tokens_saved": 0,
        "kg_concepts_expanded": 8
    }
}
```

---

## 6. Evaluation Metrics (EvaluationAgent)

```
File: ai-service/api/services/graph_cag/evaluation_agent.py

Metrics computed by EvaluationAgent:

Text Quality:
├── WER (Word Error Rate)       = edit_distance(original, corrected) / len(original)
├── TTR (Type-Token Ratio)      = unique_words / total_words
├── Error Density               = corrections / word_count
└── Word Count

Retrieval Quality:
├── Precision@K = relevant_retrieved / K
├── Recall@K    = relevant_retrieved / total_relevant
├── NDCG@K      = Σ(rel_i / log2(i+1)) / ideal_NDCG
└── MRR         = 1 / rank_of_first_relevant

Composite Score:
└── overall_weighted = 0.4*grammar + 0.3*fluency + 0.3*vocab_score
```

---

## 7. RAPID Cache Algorithm Detail

```
L0 Cache (fingerprint-based):
Key    = SHA256(query_norm + intent + level + root_concepts + turn)
Value  = CacheEntry{fingerprint, response, evidence_bundle, scores, ttl}
TTL    = 3600s (1 giờ) cho exact match

L1 Cache (graph-bucket):
Bucket = f"{level}_{sorted(concept_ids)[:3]}"
Key    = "L1:{bucket}"
Value  = BucketVersionRecord{nu_graph, nu_policy, nu_profile, t_refresh}
TTL    = 7200s (2 giờ)

Invalidation:
- nu_graph bump → tất cả L1 buckets invalid
- nu_policy bump → tất cả L0/L1 invalid
- nu_profile bump → user-specific entries invalid
- t_refresh + TTL expired → invalid
```

---

## 8. Performance Characteristics

| Scenario | Path | Latency | Model |
|---------|------|---------|-------|
| Cache L0 hit (exact) | fast | < 10ms | None |
| Cache L1 hit (bucket) | fast | < 50ms | None |
| Simple greeting | slow | ~3s | gemma2:2b (local) |
| Grammar query | slow | ~2s | Gemini (cloud) |
| Complex analysis | slow | ~20s | qwen3:4b-thinking (local) |
| Voice (full) | slow | ~5-8s | Whisper + Gemini + HuBERT |

---

## 9. Streaming Pipeline (lexi_chat.py)

```
File: ai-service/api/routes/lexi_chat.py (50KB)

TRACECAG analyze()
    → Streaming response via SSE or WebSocket
    → Client receives:
       {"event": "thinking", "data": {...}}
       {"event": "chunk", "data": "Great attempt! However..."}
       {"event": "corrections", "data": [{...}]}
       {"event": "scores", "data": {...}}
       {"event": "done", "data": {...}}
```

---

*Tham khảo: [RPT-019](RPT-019_AI_SERVICE_DEEP_DIVE.md) | [RPT-016](RPT-016_GRAPHCAG_KG_REDIS_CACHE.md) | [RPT-018](RPT-018_FEATURE_ANALYSIS.md)*
