
# LexiLingo AI Architecture v2.0

> **Document**: Kiến trúc hệ thống AI cho ứng dụng học tiếng Anh
> **Version**: 2.0 (Optimized)
> **Last Updated**: January 2026

---

## Mục lục

1. [Tổng quan hệ thống](#1-tổng-quan-hệ-thống)
2. [Kiến trúc chi tiết](#2-kiến-trúc-chi-tiết)
3. [Component Details](#3-component-details)
4. [LoRA Fine-tuning Architecture](#4-lora-fine-tuning-architecture)
5. [Training Strategy](#5-training-strategy)
6. [Performance Metrics](#6-performance-metrics)

---

## 1. Tổng quan hệ thống

### 1.1 Design Principles

```
┌─────────────────────────────────────────────────────────────────┐
│                    DESIGN PRINCIPLES                            │
├─────────────────────────────────────────────────────────────────┤
│  [*] Hybrid Models: Qwen (English) + LLaMA3 (Vietnamese)          │
│  [*] Unified Adapter: 1 adapter xử lý 4 tasks (giảm latency 75%)  │
│  [*] Lazy Loading: LLaMA3-VI chỉ load khi cần giải thích VI       │
│  [*] Parallel Processing: Pronunciation analysis chạy song song   │
│  [*] Caching: Redis cho learner profiles + common responses       │
│  [*] Fallback: Error handling với graceful degradation            │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Tech Stack

| Component | Technology | Size | Latency |
|-----------|------------|------|---------|
| STT | Faster-Whisper v3 | 244MB | 50-100ms |
| Context Encoder | all-MiniLM-L6-v2 | 22MB | 15ms |
| NLP (English) | Qwen3-1.7B + Unified LoRA | 1.5GB + 80MB | 100-150ms |
| NLP (Vietnamese) | LLaMA3-8B-VI (lazy) | 8GB | 200ms |
| Knowledge Graph | NetworkX / KuzuDB | <50MB | <5ms |
| Pronunciation | HuBERT-large | 960MB | 100-200ms |
| TTS | Piper VITS | 30-60MB | 100-300ms |
| Cache | Redis | - | <5ms |

---

## 2. Kiến trúc chi tiết

### 2.1 Main Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│                     USER INPUT LAYER                            │
└─────────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │                                           │
        ▼                                           ▼
┌───────────────┐                          ┌───────────────┐
│  Voice Input  │                          │  Text Input   │
│  (Microphone) │                          │  (Keyboard)   │
└───────┬───────┘                          └───────┬───────┘
        │                                           │
        ▼                                           │
┌──────────────────────────────────────────────────────────────────┐
│                    STT: WHISPER v3                               │
├──────────────────────────────────────────────────────────────────┤
│  Model: openai/whisper + CTranslate2 optimization                │
│  Features:                                                       │
│  • VAD (Silero): Voice Activity Detection                        │
│  • Streaming: Real-time transcription                            │
│  • Word timestamps: Alignment for pronunciation                  │
│  Performance: WER <10% (ESL), RTF <0.3, Latency <100ms           │
└──────────────────────────────────────────────────────────────────┘
        │
        │ Text + Word Timestamps
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                    CONTEXT MANAGER                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Context Encoder: all-MiniLM-L6-v2 (22MB)                  │  │
│  │  • 3x lighter than BERT (22MB vs 440MB)                    │  │
│  │  • Sentence embeddings (384-dim)                           │  │
│  │  • Latency: ~15ms                                          │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Conversation History Buffer                               │  │
│  │  • Last 5 turns (sliding window)                           │  │
│  │  • Context embedding aggregation                           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Redis Cache: Learner Profile                              │  │
│  │  • learner:{id}:level → "A2" / "B1" / "B2"                 │  │
│  │  • learner:{id}:errors → ["past_tense", "articles"]        │  │
│  │  • learner:{id}:sessions → Last 10 conversation summaries  │  │
│  │  • TTL: 30 days                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Knowledge Graph (Semantic Memory)                         │  │
│  │  • Nodes: Vocab (Word), Grammar (Rule), Topic (Concept)    │  │
│  │  • Edges: "is_a", "related_to", "prerequisite_of"          │  │
│  │  • Purpose: Structured RAG & Curriculum guiding            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
        │
        │ Context Vector + Learner Profile
        ▼
┌──────────────────────────────────────────────────────────────────┐
│                    ORCHESTRATOR (CORE ENGINE)                    │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Central Coordinator: Điều phối toàn bộ AI pipeline              │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Phase 1: Task Analysis                                    │  │
│  │  ────────────────────────────────────────────────────────  │  │
│  │  Input: User text + context + learner profile              │  │
│  │                                                            │  │
│  │  Analysis:                                                 │  │
│  │  • Detect task type: fluency/grammar/vocab/dialogue        │  │
│  │  • Assess complexity: simple/medium/complex                │  │
│  │  • Check learner level: A2/B1/B2                           │  │
│  │  • Identify required components                            │  │
│  │                                                            │  │
│  │  Output: Execution plan                                    │  │
│  │    {                                                       │  │
│  │      "primary_tasks": ["grammar", "fluency"],              │  │
│  │      "parallel_tasks": ["pronunciation"],                  │  │
│  │      "need_vietnamese": false,                             │  │
│  │      "strategy": "socratic_questioning"                    │  │
│  │    }                                                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Phase 2: Resource Allocation                              │  │
│  │  ────────────────────────────────────────────────────────  │  │
│  │  • Check GPU/CPU availability                              │  │
│  │  • Load required models (lazy loading)                     │  │
│  │  • Allocate memory budgets                                 │  │
│  │  • Setup parallel executors                                │  │
│  │                                                            │  │
│  │  Resource Manager:                                         │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ Qwen Base: Always loaded (1.6GB)                     │  │  │
│  │  │ Unified Adapter: Loaded on-demand (80MB)             │  │  │
│  │  │ LLaMA3-VI: Lazy load if needed (8GB)                 │  │  │
│  │  │ HuBERT: Load for voice input only (2GB)              │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Phase 3: Execution Coordination                           │  │
│  │  ────────────────────────────────────────────────────────  │  │
│  │  Sequential Tasks:                                         │  │
│  │  1. Qwen Unified Adapter → Comprehensive analysis          │  │
│  │    Knowledge Graph → Query related concepts (Graph RAG)    │  │
│  │  •  - Fluency score                                        │  │
│  │     - Grammar correction                                   │  │
│  │     - Vocabulary level                                     │  │
│  │     - Tutor response                                       │  │
│  │                                                            │  │
│  │  Parallel Tasks (async):                                   │  │
│  │  • HuBERT → Pronunciation analysis (if voice input)        │  │
│  │  • Cache lookup → Check for similar responses              │  │
│  │  • Redis update → Save learner progress                    │  │
│  │                                                            │  │
│  │  Conditional Tasks:                                        │  │
│  │  • IF confidence < 0.8 OR level == "A2":                   │  │
│  │    → Load LLaMA3-VI for Vietnamese explanation             │  │
│  │                                                            │  │
│  │  Execution Flow:                                           │  │
│  │  ┌─────────────┐                                           │  │
│  │  │   Start     │                                           │  │
│  │  └──────┬──────┘                                           │  │
│  │         ▼                                                  │  │
│  │  ┌─────────────┐     ┌─────────────┐                       │  │
│  │  │ Qwen        │────▶│  HuBERT     │ (parallel)            │  │
│  │  │ Analysis    │     │ Phonemes    │                       │  │
│  │  └──────┬──────┘     └──────┬──────┘                       │  │
│  │         ▼                   ▼                              │  │
│  │  ┌─────────────────────────────┐                           │  │
│  │  │   Wait for all tasks        │                           │  │
│  │  └──────────┬──────────────────┘                           │  │
│  │             ▼                                              │  │
│  │  ┌──────────────────┐                                      │  │
│  │  │ IF need VI?      │                                      │  │
│  │  └────┬─────────┬───┘                                      │  │
│  │       Yes       No                                         │  │
│  │       ▼         ▼                                          │  │
│  │  ┌─────────┐  Skip                                         │  │
│  │  │ LLaMA3  │                                               │  │
│  │  └────┬────┘                                               │  │
│  │       ▼                                                    │  │
│  │  ┌──────────────────┐                                      │  │
│  │  │ Fusion & Aggr.   │                                      │  │
│  │  └────┬─────────────┘                                      │  │
│  │       ▼                                                    │  │
│  │  ┌──────────────────┐                                      │  │
│  │  │   Response       │                                      │  │
│  │  └──────────────────┘                                      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Phase 4: Error Handling & Fallback                        │  │
│  │  ────────────────────────────────────────────────────────  │  │
│  │  Try-Catch Hierarchy:                                      │  │
│  │                                                            │  │
│  │  Level 1: Component Failure                                │  │
│  │  • If Qwen fails → Use cached response or rule-based       │  │
│  │  • If HuBERT fails → Skip pronunciation, continue          │  │
│  │  • If LLaMA3-VI fails → Use English only                   │  │
│  │                                                            │  │
│  │  Level 2: Timeout Management                               │  │
│  │  • Task timeout: 500ms per component                       │  │
│  │  • Total timeout: 2s for full pipeline                     │  │
│  │  • If timeout → Return partial results                     │  │
│  │                                                            │  │
│  │  Level 3: Resource Exhaustion                              │  │
│  │  • GPU OOM → Offload to CPU, reduce batch size             │  │
│  │  • CPU overload → Queue request, return cached             │  │
│  │                                                            │  │
│  │  Graceful Degradation:                                     │  │
│  │  Full → Basic → Minimal                                    │  │
│  │  ↓      ↓       ↓                                          │  │
│  │  All   Only     Rule-based                                 │  │
│  │  AI    Qwen     grammar check                              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Phase 5: State Management                                 │  │
│  │  ────────────────────────────────────────────────────────  │  │
│  │  Conversation State:                                       │  │
│  │  • session_id: Unique per conversation                     │  │
│  │  • turn_count: Number of exchanges                         │  │
│  │  • topic_context: Current discussion topic                 │  │
│  │  • error_history: Recent mistakes for tracking             │  │
│  │                                                            │  │
│  │  Model State:                                              │  │
│  │  • loaded_models: ["qwen", "hubert"]                       │  │
│  │  • active_adapter: "unified"                               │  │
│  │  • memory_usage: 3.2GB / 8GB                               │  │
│  │                                                            │  │
│  │  Cache State:                                              │  │
│  │  • cache_hits: 12 / 20 requests (60%)                      │  │
│  │  • recent_responses: Last 10 cached                        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Monitoring & Logging:                                           │
│  • Latency per component (STT: 80ms, Qwen: 120ms...)             │
│  • Resource usage (GPU: 45%, RAM: 4.2GB)                         │
│  • Error rates by component                                      │
│  • Cache hit rates                                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
        │
        │
   ┌────┴────────────────────────────────────────┐
   │                                             │
   ▼                                             ▼
┌─────────────────────────────┐    ┌─────────────────────────────┐
│   PRIMARY: Qwen3-1.7B     │    │   PARALLEL: HuBERT-large    │
│   + Unified LoRA Adapter    │    │   Pronunciation Analysis    │
├─────────────────────────────┤    ├─────────────────────────────┤
│                             │    │                             │
│  Config:                    │    │  Model: hubert-large-ls960  │
│  • LoRA rank: r=48          │    │  • Phoneme recognition      │
│  • Alpha: α=96              │    │  • CTC decoding             │
│  • Target: All 7 modules    │    │  • Forced alignment (DTW)   │
│  • Trainable: ~45M (3.0%)   │    │                             │
│                             │    │  Output:                    │
│  Tasks (JSON output):       │    │  • Phoneme accuracy: 0.85   │
│  • fluency_score: 0.87      │    │  • Errors: [/θ/→/s/]        │
│  • vocabulary_level: "B1"   │    │  • Prosody score: 0.78      │
│  • grammar_errors: [...]    │    │                             │
│  • tutor_response: "..."    │    │  Latency: 100-200ms         │
│                             │    │                             │
│  Latency: 100-150ms         │    │                             │
│                             │    │                             │
└──────────────┬──────────────┘    └───────────────┬─────────────┘
               │                                   │
               │                                   │
               ▼                                   │
┌─────────────────────────────┐                    │
│  SECONDARY: LLaMA3-8B-VI    │                    │
│  (Lazy Load - On Demand)    │                    │
├─────────────────────────────┤                    │
│                             │                    │
│  Trigger Conditions:        │                    │
│  • confidence < 0.8         │                    │
│  • learner_level == "A2"    │                    │
│  • explicit VI request      │                    │
│                             │                    │
│  Output:                    │                    │
│  • Vietnamese explanation   │                    │
│  • Grammar rule in VI       │                    │
│  • Encouragement in VI      │                    │
│                             │                    │
│  Loading Strategy:          │                    │
│  • CPU offload (8GB RAM)    │                    │
│  • 4-bit quantization       │                    │
│  • Lazy: Only load when     │                    │
│    needed (~2s first load)  │                    │
│                             │                    │
│  Latency: 200ms (warm)      │                    │
│                             │                    │
└──────────────┬──────────────┘                    │
               │                                   │
               └─────────────┬─────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    ATTENTION FUSION LAYER                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Mechanism: Cross-Attention                                      │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Q = Qwen_output (English analysis)                        │  │
│  │  K = LLaMA_output (Vietnamese explanation)                 │  │
│  │  V = Context_embedding (conversation history)              │  │
│  │                                                            │  │
│  │  Attention(Q, K, V) = softmax(QK^T / √d_k) * V             │  │
│  │                                                            │  │
│  │  Output = LayerNorm(Q + Attention + FFN)                   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Fusion Weights (learned):                                       │
│  • w_qwen: 0.7 (English primary)                                 │
│  • w_llama: 0.2 (Vietnamese when needed)                         │
│  • w_context: 0.1 (conversation coherence)                       │
│                                                                  │
│  Combined Output:                                                │
│  {                                                               │
│    "analysis": { fluency, vocab, grammar, pronunciation },       │
│    "response_en": "Great job! ...",                              │
│    "response_vi": "Bạn làm tốt lắm! ..." (optional),             │
│    "confidence": 0.92                                            │
│  }                                                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    FEEDBACK STRATEGY ENGINE                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Strategy Selection (based on analysis):                         │
│                                                                  │
│  ┌─────────────┬─────────────┬─────────────┬─────────────┐       │
│  │   PRAISE    │   CORRECT   │   EXPLAIN   │   DRILL     │       │
│  ├─────────────┼─────────────┼─────────────┼─────────────┤       │
│  │ No errors   │ 1-2 errors  │ 3+ errors   │ Repeated    │       │
│  │ fluency>0.8 │ fluency>0.6 │ fluency<0.6 │ same error  │       │
│  └─────────────┴─────────────┴─────────────┴─────────────┘       │
│                                                                  │
│  Level Adaptation:                                               │
│  • A2: Simple words, short sentences, more Vietnamese            │
│  • B1: Natural conversation, some complexity                     │
│  • B2: Near-native interaction, minimal hand-holding             │
│                                                                  │
│  Response Length: 20-50 words (adjustable by level)              │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    RESPONSE AGGREGATION                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Final Response Format:                                          │
│  {                                                               │
│    "text": "Great job! Your sentence is correct. To sound        │
│             more natural, try 'I enjoy learning English'...",    │
│    "vietnamese_hint": "Bạn có thể nói: 'I enjoy...' để tự        │
│                        nhiên hơn" (if A2 or low confidence),     │
│    "pronunciation_tip": "Focus on the 'th' sound in 'think'",    │
│    "score": {                                                    │
│      "fluency": 0.87,                                            │
│      "grammar": 1.0,                                             │
│      "vocabulary": "B1",                                         │
│      "pronunciation": 0.82                                       │
│    },                                                            │
│    "next_action": "continue_conversation"                        │
│  }                                                               │
│                                                                  │
│  Cache Common Responses:                                         │
│  • "Great job!" → cached audio                                   │
│  • "Try again" → cached audio                                    │
│  • Common corrections → pre-generated                            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    TTS: PIPER VITS                               │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Model: en_US-lessac-medium (VITS-based)                         │
│  Size: 30-60MB                                                   │
│  Latency: 100-300ms                                              │
│                                                                  │
│  Features:                                                       │
│  • Offline capable (no internet required)                        │
│  • Natural prosody                                               │
│  • Adjustable speech rate                                        │
│                                                                  │
│  Output: 22kHz WAV/MP3                                           │
│                                                                  │
│  Caching Strategy:                                               │
│  • Pre-generate common phrases                                   │
│  • Cache by text hash (MD5)                                      │
│  • TTL: 7 days                                                   │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
                             │
                             │ Audio + Text Response
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│                    USER OUTPUT                                   │
├──────────────────────────────────────────────────────────────────┤
│  • Audio playback (TTS response)                                 │
│  • Visual feedback (scores, corrections)                         │
│  • Vietnamese explanation (if needed)                            │
│  • Next suggested action                                         │
└──────────────────────────────────────────────────────────────────┘
                             │
                             (loop) (conversation loop)
```

---

### 2.2 Knowledge-Centric Pipeline v3 (LLM + KG + TraceCAG Cache)

Mục tiêu của V3 là biến “Knowledge Graph” từ *ô trong sơ đồ* thành “hệ tri thức vận hành được”, đồng thời giữ phản hồi nhanh bằng cách tách **Fast Path / Slow Path / Background Path**.

Quy ước trong tài liệu này:
- **TraceCAG** = pipeline hội thoại có **cache gate** (RAPID L0/L1) + KG retrieval + grounded generation.
- **CAG (Content Auto-Generation)** = dịch vụ sinh bài luyện/lộ trình học chạy nền, tách riêng khỏi pipeline hội thoại TraceCAG.

#### 2.2.1 Ba đường chạy (Fast/Slow/Background)

```
┌──────────────────────────────────────────────────────────────────┐
│                      V3 EXECUTION PATHS                          │
├──────────────────────────────────────────────────────────────────┤
│  FAST PATH (50-150ms)                                            │
│  - Cache hit (exact/semantic)                                    │
│  - Rule-based / template feedback for common errors              │
│  - Return short helpful response + 1 clarifying question         │
│                                                                  │
│  SLOW PATH (250-1200ms)                                          │
│  - Diagnose → Hybrid Retrieval (Vector + KG) → Grounded Generate │
│  - Returns linked concepts + actionable fix                      │
│                                                                  │
│  BACKGROUND PATH (async, non-blocking)                           │
│  - Update learner profile + write KG edges/weights               │
│  - Trigger lesson generation service (Content Auto-Generation)   │
│  - Summarize session, metrics logging                            │
└──────────────────────────────────────────────────────────────────┘
```

#### 2.2.2 Pipeline chi tiết (grounded + tri thức liên kết)

```
┌──────────────────────┐
│  Input Normalization │  (STT optional, lang detect, cleanup)
└──────────┬───────────┘
                     ▼
┌──────────────────────┐
│ Context Fetch        │  (history, learner profile, embeddings)
└──────────┬───────────┘
                     ▼
┌──────────────────────┐
│ Diagnose (cheap)     │  intent/skill/root-cause/confidence
└───────┬─────────┬────┘
                │         │
                │         ├───────────────┐
                │         │               │
                ▼         ▼               ▼
    ┌──────────┐  ┌──────────────────────┐   ┌──────────────────────────┐
    │ Cache    │  │ Hybrid Retrieval     │   │ Clarify Question (if low)│
    │ Gate     │  │ Vector → KG expand   │   │ 1 question, fast reply   │
    └────┬─────┘  └──────────┬───────────┘   └──────────────────────────┘
             │                  ▼
             │        ┌──────────────────────┐
             │        │ Evidence Bundle      │  concepts + examples + rules
             │        └──────────┬───────────┘
             │                   ▼
             └──────────────────►┌──────────────────────┐
                                 │ Grounded Generation  │  LLM constrained to evidence
                                 └──────────┬───────────┘
                                            ▼
                                 ┌──────────────────────┐
                                 │ Verify + Score       │  JSON schema + confidence
                                 └──────────┬───────────┘
                                            ▼
                                 ┌──────────────────────┐
                                 │ Respond              │  EN + optional VI
                                 └──────────┬───────────┘
                                            ▼
                                 ┌──────────────────────┐
                                 │ Background Jobs      │  KG update + cache/profile sync + optional lesson generation
                                 └──────────────────────┘
```

#### 2.2.3 Hợp đồng dữ liệu (JSON) để TraceCAG chạy ổn định (trước đây là Orchestrator)

**A) `DiagnosisV3` (đầu ra của bước Diagnose)**

```json
{
    "intent": "fix_grammar|explain_rule|practice|translate|general_chat",
    "skill": "grammar|vocabulary|fluency|pronunciation|mixed",
    "user_problem": "short natural language summary",
    "suspected_errors": [{"type": "verb_tense", "span": "I goes"}],
    "root_cause_candidates": ["concept:grammar.subject_verb_agreement"],
    "need_vietnamese": false,
    "confidence": 0.0,
    "next_best_action": "answer|ask_clarify|generate_practice"
}
```

**B) `RetrievalBundleV3` (bằng chứng tri thức để LLM bám vào)**

```json
{
    "query": "string",
    "vector_hits": [
        {"id": "concept:grammar.present_simple", "score": 0.82, "snippet": "..."}
    ],
    "kg_hits": {
        "seed_nodes": ["concept:grammar.subject_verb_agreement"],
        "expanded_nodes": [
            {"id": "concept:grammar.third_person_s", "relation": "related_to"},
            {"id": "concept:grammar.past_time_markers", "relation": "prerequisite_of"}
        ],
        "paths": [
            {"from": "concept:grammar.subject_verb_agreement", "to": "concept:grammar.third_person_s", "hops": 1}
        ]
    },
    "examples": [
        {"good": "I go to school.", "bad": "I goes to school.", "why": "I + base verb"}
    ]
}
```

**C) `TutorResponseV3` (phản hồi cuối, có liên kết tri thức)**

```json
{
    "tutor_response": "string",
    "corrections": [{"error": "I goes", "correction": "I go", "type": "subject_verb_agreement"}],
    "linked_concepts": [
        {"id": "concept:grammar.subject_verb_agreement", "weight": 0.9}
    ],
    "action_plan": [
        {"action": "practice", "concept": "concept:grammar.subject_verb_agreement", "count": 5}
    ],
    "confidence": 0.0,
    "metadata": {
        "path": "fast|slow",
        "latency_ms": 0,
        "models_used": ["qwen"],
        "cache": {"hit": false, "key": "..."}
    }
}
```

**D) `CAGLessonRequestV3` (request gửi sang dịch vụ Content Auto-Generation chạy nền)**

```json
{
    "user_id": "...",
    "level": "A2|B1|B2",
    "target_concepts": ["concept:grammar.subject_verb_agreement"],
    "error_patterns": ["subject_verb_agreement"],
    "constraints": {"duration_min": 10, "types": ["grammar", "vocabulary"]}
}
```

#### 2.2.4 Những cải tiến then chốt để đạt “tri thức liên kết, bắt đúng vấn đề”

- **Hybrid Retrieval bắt buộc**: Vector để bắt ngôn ngữ tự nhiên + KG để suy ra prerequisite/root-cause (1–2 hops) và tạo “đường giải thích”.
- **Diagnose tách riêng**: bước rẻ, ổn định, trả JSON (intent/skill/root-cause/confidence) để quyết định hỏi làm rõ hay đi thẳng.
- **Grounded Generation**: LLM phải nhận `RetrievalBundleV3` và bị ràng buộc trả lời dựa trên evidence + trả `linked_concepts`.
- **TraceCAG ưu tiên phản hồi nhanh**: cache gate chạy trước để quyết định reuse/patch/full retrieval.
- **Content Auto-Generation không chặn phản hồi**: dịch vụ sinh lesson chạy nền dựa trên `target_concepts` và `error_patterns`.

#### 2.2.5 Mapping theo các Phase truyền thống

- **Phase 1 (Task Analysis)**: sinh `DiagnosisV3` (cheap classifier + rules + light LLM).
- **Phase 3 (Execution)**:
    - Fast path: `cache_gate_node` (RAPID L0/L1) → response.
    - Slow path: build `RetrievalBundleV3` (vector + KG) → grounded generation → verify.
- **Phase 5/6 (State Management)**: emit background jobs: cập nhật learner profile + KG writer + invoke Content Auto-Generation service.

## 3. Component Details

### 3.1 Error Handling & Fallback

```
┌──────────────────────────────────────────────────────────────────┐
│                    ERROR HANDLING STRATEGY                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Level 1: Component Timeout                                      │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  if STT timeout (>500ms):                                  │  │
│  │      → Retry with smaller audio chunk                      │  │
│  │      → Fallback to text input prompt                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Level 2: Model Failure                                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  if Qwen fails:                                            │  │
│  │      → Use cached similar response                         │  │
│  │      → Fallback to rule-based grammar check                │  │
│  │  if LLaMA3-VI fails:                                       │  │
│  │      → Skip Vietnamese, use English only                   │  │
│  │  if HuBERT fails:                                          │  │
│  │      → Skip pronunciation, return text analysis only       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Level 3: System Overload                                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  if GPU memory >90%:                                       │  │
│  │      → Offload LLaMA3-VI to CPU                            │  │
│  │      → Reduce batch size                                   │  │
│  │  if latency >2s:                                           │  │
│  │      → Return partial results                              │  │
│  │      → Queue full analysis for background                  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Pipeline Execution Architecture

The previous `AIOrchestrator` conceptual flow has been refactored
into a LangGraph StateGraph-based architecture. Below is the mapping:

| Old Conceptual Phase | LangGraph Implementation |
|---|---|
| Phase 1: Task Analysis | `input_node` + `diagnose_node` |
| Phase 2: Resource Alloc | Deferred to `ModelGateway` (lazy load) |
| Phase 3a: Cache Decision| `cache_gate_node` (RAPID algorithm) |
| Phase 3b: KG Expansion  | `kg_expand_node` (parallel w/ diagnose) |
| Phase 3c: Routing       | `route_after_diagnosis` edge |
| Phase 3d: Retrieval     | `retrieve_node` |
| Phase 3e: Generation    | `generate_node` |
| Phase 4: Result Aggr    | `_format_response()` in `graph.py` |
| Phase 5: State Update   | Background job (async, non-blocking) |

Each node is an async function that reads/writes to `TraceCAGState`.

### 3.3 Pipeline Benefits & Metrics

```
┌──────────────────────────────────────────────────────────────────┐
│              WHY ORCHESTRATOR IS ESSENTIAL                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Problem Without TraceCAG:                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  [!] Tight coupling between components                       │  │
│  │  [!] No centralized error handling                           │  │
│  │  [!] Inefficient resource usage (all models always loaded)   │  │
│  │  [!] No task prioritization                                  │  │
│  │  [!] Difficult to add new features                           │  │
│  │  [!] No visibility into pipeline performance                 │  │
│  │  [!] Hard to test individual components                      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Solutions With TraceCAG:                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  [*] Single responsibility principle                         │  │
│  │  [*] Centralized error handling & fallback                   │  │
│  │  [*] Lazy loading - 60% memory savings                       │  │
│  │  [*] Intelligent task routing                                │  │
│  │  [*] Easy to extend (add new adapters/models)                │  │
│  │  [*] Built-in monitoring & telemetry                         │  │
│  │  [*] Testable components in isolation                        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Performance Improvements:                                       │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Metric              │ Before    │ After     │ Improvement │  │
│  │  ───────────────────────────────────────────────────────   │  │
│  │  Avg Latency         │ 800ms     │ 350ms     │ -56%        │  │
│  │  Memory Usage        │ 12GB      │ 4.8GB     │ -60%        │  │
│  │  Cache Hit Rate      │ N/A       │ 45%       │ +45%        │  │
│  │  Error Recovery      │ Manual    │ Auto      │ 100%        │  │
│  │  Parallel Execution  │ No        │ Yes       │ 2x faster   │  │
│  │  Code Maintainability│ Complex   │ Clean     │ +70%        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Key Architectural Benefits:                                     │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  1. Separation of Concerns                                 │  │
│  │     • LangGraph handles WHAT to run                     │  │
│  │     • Components handle HOW to run                         │  │
│  │                                                            │  │
│  │  2. Flexibility                                            │  │
│  │     • Easy to swap models (e.g., Qwen → GPT-4)             │  │
│  │     • Add new tasks without changing core logic            │  │
│  │                                                            │  │
│  │  3. Observability                                          │  │
│  │     • Track latency per component                          │  │
│  │     • Monitor resource usage                               │  │
│  │     • Analyze failure patterns                             │  │
│  │                                                            │  │
│  │  4. Scalability                                            │  │
│  │     • Queue long-running tasks                             │  │
│  │     • Load balancing across GPUs                           │  │
│  │     • Horizontal scaling ready                             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 3.4 Caching Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    REDIS CACHE SCHEMA                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Learner Profile:                                                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Key: learner:{user_id}:profile                            │  │
│  │  Value: {                                                  │  │
│  │    "level": "A2",                                          │  │
│  │    "native_language": "Vietnamese",                        │  │
│  │    "common_errors": ["past_tense", "articles"],            │  │
│  │    "vocabulary_count": 1500,                               │  │
│  │    "sessions_completed": 25,                               │  │
│  │    "last_active": "2026-01-15T10:30:00Z"                   │  │
│  │  }                                                         │  │
│  │  TTL: 30 days                                              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Conversation History:                                           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Key: conversation:{session_id}:history                    │  │
│  │  Value: [                                                  │  │
│  │    {"role": "user", "text": "...", "timestamp": "..."},    │  │
│  │    {"role": "assistant", "text": "...", "scores": {...}}   │  │
│  │  ]                                                         │  │
│  │  TTL: 24 hours (session-based)                             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Response Cache:                                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  ═══ L0 EXACT-MATCH CACHE ═══                              │  │
│  │  Key format: v1:resp:{MD5(clean(query) || level)}          │  │
│  │  Hit condition: exact query + exact level match            │  │
│  │  Hit rate: ~50% on repeated-query workload                 │  │
│  │  Hit latency: ~4ms                                         │  │
│  │  TTL: 24 hours (dynamically set per entry)                 │  │
│  │                                                            │  │
│  │  ═══ L1 CONCEPT-STATE BUCKET CACHE ═══                     │  │
│  │  Bucket key: v1:resp_bucket:{MD5(...)                      │  │
│  │  Hit condition: PCC gate (Intent, Concepts, Level)         │  │
│  │  Hit latency: ~5-30ms                                      │  │
│  │  Hit rate: Target 10-15%                                   │  │
│  │  TTL: 2 hours (bucket), 24 hours (entries)                 │  │
│  │                                                            │  │
│  │  ═══ L2 RECONSTRUCTION ═══                                 │  │
│  │  Cost: 110-180ms (rule-based) or 1000ms+ (LLM)             │  │
│  │                                                            │  │
│  │  ═══ BUCKET VERSION INVALIDATION ═══                       │  │
│  │  v_b = {nu_graph, nu_policy, nu_profile, t_refresh}        │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  TTS Audio Cache:                                                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Key: tts:{text_hash}                                      │  │
│  │  Value: Binary audio data (base64)                         │  │
│  │  TTL: 7 days                                               │  │
│  │  Pre-cached: 100 common phrases                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 4. LoRA Fine-tuning Architecture

### 4.1 Unified Adapter (Recommended for Production)

```
┌──────────────────────────────────────────────────────────────────┐
│              UNIFIED LoRA ADAPTER (Qwen3-1.7B)                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Configuration:                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Base Model: Qwen/Qwen3-1.7B                    │  │
│  │  LoRA Rank: r=48                                           │  │
│  │  LoRA Alpha: α=96                                          │  │
│  │  Target Modules: [                                         │  │
│  │    "q_proj", "k_proj", "v_proj", "o_proj",                 │  │
│  │    "gate_proj", "up_proj", "down_proj"                     │  │
│  │  ]                                                         │  │
│  │  Trainable Parameters: ~45M (3.0% of base)                 │  │
│  │  Adapter Size: ~80MB                                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Tasks Supported:                                                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Task 1: fluency_scoring                                   │  │
│  │    Input: "Task: fluency_scoring\nText: {text}"            │  │
│  │    Output: {"fluency_score": 0.87, "reasoning": "..."}     │  │
│  │                                                            │  │
│  │  Task 2: vocabulary_classification                         │  │
│  │    Input: "Task: vocabulary_classification\nText: {text}"  │  │
│  │    Output: {"level": "B1", "key_words": [...]}             │  │
│  │                                                            │  │
│  │  Task 3: grammar_correction                                │  │
│  │    Input: "Task: grammar_correction\nText: {text}"         │  │
│  │    Output: {"corrected": "...", "errors": [...]}           │  │
│  │                                                            │  │
│  │  Task 4: dialogue_response (AI Tutor Mode)                 │  │
│  │    Input: "Task: dialogue_response\nText: {text}\n         │  │
│  │            Context: {history}\nStrategy: {socratic/        │  │
│  │            scaffolding/feedback}"                          │  │
│  │    Output: {                                               │  │
│  │      "response": "Good start! What tense describes         │  │
│  │                   past actions?",                          │  │
│  │      "strategy": "socratic_questioning",                   │  │
│  │      "pedagogical_goal": "guide_to_discovery"              │  │
│  │    }                                                       │  │
│  │                                                            │  │
│  │  Task 5: comprehensive_analysis (ALL TASKS)                │  │
│  │    Input: "Task: comprehensive_analysis\nText: {text}"     │  │
│  │    Output: {                                               │  │
│  │      "fluency_score": 0.87,                                │  │
│  │      "vocabulary_level": "B1",                             │  │
│  │      "grammar": {"corrected": "...", "errors": [...]},     │  │
│  │      "response": "Great job! ..."                          │  │
│  │    }                                                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Performance:                                                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Latency: 100-150ms (single call for all tasks)            │  │
│  │  Quality: 95-97% of individual adapters                    │  │
│  │  Memory: 1.6GB (base) + 80MB (adapter) = ~1.7GB            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 Individual Adapters (Development/Debugging)

```
┌──────────────────────────────────────────────────────────────────┐
│           4 INDIVIDUAL LoRA ADAPTERS (Task-Specific)             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  [1] Fluency Scoring Adapter                                     │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  LoRA: r=32, α=64                                          │  │
│  │  Target: All 7 modules                                     │  │
│  │  Trainable: ~25M params                                    │  │
│  │  Output: Score 0.0-1.0 + reasoning                         │  │
│  │  Metrics: MAE < 0.12 (dev), < 0.15 (prod)                  │  │
│  │  Dataset: 1,500 samples (EFCAMDAT, TOEFL11)                │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  [2] Vocabulary Classification Adapter                           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  LoRA: r=32, α=64                                          │  │
│  │  Target: q_proj, v_proj, o_proj                            │  │
│  │  Trainable: ~15M params                                    │  │
│  │  Output: A2/B1/B2 level + key words                        │  │
│  │  Accuracy: 90% (dev), 86% (prod)                           │  │
│  │  Dataset: 2,500 samples (CEFR corpus)                      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  [3] Grammar Correction Adapter                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  LoRA: r=32, α=64                                          │  │
│  │  Target: All attention + MLP                               │  │
│  │  Trainable: ~25M params                                    │  │
│  │  Output: Corrected text + explanations                     │  │
│  │  F0.5: 68 (dev), 62 (prod)                                 │  │
│  │  Dataset: 9,200 samples (BEA-2019, FCE, CoNLL)             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  [4] Dialogue Response Adapter (AI Tutor)                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  LoRA: r=32, α=64                                          │  │
│  │  Target: All 7 modules                                     │  │
│  │  Trainable: ~25M params                                    │  │
│  │  Output: Pedagogical tutor response                        │  │
│  │  Quality: 96% (human evaluation)                           │  │
│  │                                                            │  │
│  │  Datasets:                                                 │  │
│  │  • AutoTutor Dialogue Corpus: 1,200 tutoring sessions      │  │
│  │    - Socratic questioning strategies                       │  │
│  │    - Scaffolding techniques                                │  │
│  │    - Feedback patterns                                     │  │
│  │  • Intel/orca: 1,500 instruction samples                   │  │
│  │  • Custom ESL tutoring: 800 samples                        │  │
│  │  Total: 3,500 samples                                      │  │
│  │                                                            │  │
│  │  Tutoring Strategies:                                      │  │
│  │  1. Socratic Method: Guide with questions                  │  │
│  │     "What tense should we use for past events?"            │  │
│  │  2. Scaffolding: Break into smaller steps                  │  │
│  │     "Let's first check the verb, then the tense"           │  │
│  │  3. Positive Feedback: Encourage progress                  │  │
│  │     "Good try! You got the verb right..."                  │  │
│  │  4. Hint-giving: Progressive disclosure                    │  │
│  │     "Think about when the action happened..."              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 4.3 LLaMA3-VI Adapter (Vietnamese Explanations)

```
┌──────────────────────────────────────────────────────────────────┐
│              LLaMA3-8B VIETNAMESE ADAPTER                        │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Base Model: meta-llama/Llama-3-8B (Vietnamese fine-tuned)       │
│  LoRA: r=16, α=32                                                │
│  Target: q_proj, v_proj                                          │
│  Trainable: ~8M params                                           │
│                                                                  │
│  Tasks:                                                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  1. Grammar Explanation (Vietnamese)                       │  │
│  │     Input: "Explain this error in Vietnamese: {error}"     │  │
│  │     Output: "Lỗi này là do dùng sai thì quá khứ..."        │  │
│  │                                                            │  │
│  │  2. Learning Tips (Vietnamese)                             │  │
│  │     Input: "Give tips for: {topic}"                        │  │
│  │     Output: "Để cải thiện phát âm, bạn nên..."             │  │
│  │                                                            │  │
│  │  3. Encouragement (Vietnamese)                             │  │
│  │     Input: "Encourage learner for: {achievement}"          │  │
│  │     Output: "Bạn làm tốt lắm! Tiếp tục cố gắng nhé!"       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Loading Strategy:                                               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  • Lazy loading: Only load when needed                     │  │
│  │  • CPU offload: Use RAM instead of VRAM                    │  │
│  │  • 4-bit quantization: 8GB → 4GB                           │  │
│  │  • First load: ~2-3 seconds                                │  │
│  │  • Warm inference: ~200ms                                  │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 5. Training Strategy

### 5.1 Training Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│                    TRAINING PIPELINE                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Phase 1: Data Preparation (Week 1)                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Dataset Collection:                                       │  │
│  │  • Fluency: EFCAMDAT, TOEFL11 (1,500 samples)              │  │
│  │  • Vocabulary: CEFR corpus, Oxford lists (2,500 samples)   │  │
│  │  • Grammar: BEA-2019, FCE, CoNLL (9,200 samples)           │  │
│  │  • Dialogue:                                               │  │
│  │    - AutoTutor Corpus: 1,200 tutoring sessions             │  │
│  │    - Intel/orca: 1,500 instruction samples                 │  │
│  │    - Custom ESL tutoring: 800 samples                      │  │
│  │    Subtotal: 3,500 samples                                 │  │
│  │  Total: ~16,700 samples                                    │  │
│  │                                                            │  │
│  │  Data Processing:                                          │  │
│  │  • Deduplication                                           │  │
│  │  • Quality filtering (confidence > 0.8)                    │  │
│  │  • Format unification                                      │  │
│  │  • Train/Val/Test split: 80/10/10                          │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Phase 2: Qwen Unified Adapter Training (Week 2-3)               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Config:                                                   │  │
│  │  • Base: Qwen3-1.7B (4-bit quantized)           │  │
│  │  • LoRA: r=48, α=96, dropout=0.05                          │  │
│  │  • Optimizer: AdamW (lr=2e-4, weight_decay=0.01)           │  │
│  │  • Batch: 6 (gradient_accum=4 → effective 24)              │  │
│  │  • Epochs: 7                                               │  │
│  │  • Scheduler: Cosine with 3% warmup                        │  │
│  │  • Precision: BFloat16                                     │  │
│  │                                                            │  │
│  │  Training Time: ~90-120 minutes (T4 GPU)                   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Phase 3: LLaMA3-VI Adapter Training (Week 3-4)                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Dataset: Vietnamese explanations (2,000 samples)          │  │
│  │  Config:                                                   │  │
│  │  • LoRA: r=16, α=32                                        │  │
│  │  • Epochs: 5                                               │  │
│  │  • LR: 3e-4                                                │  │
│  │                                                            │  │
│  │  Training Time: ~60-90 minutes (T4 GPU)                    │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Phase 4: Fusion Layer Training (Week 4)                         │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Input: [qwen_output, llama_output, context_embedding]     │  │
│  │  Output: Combined response                                 │  │
│  │  Loss: CE + Context coherence (λ=0.1)                      │  │
│  │  Dataset: 3,000 conversation samples                       │  │
│  │                                                            │  │
│  │  Training Time: ~30-45 minutes                             │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Phase 5: End-to-End Fine-tuning (Week 5, Optional)              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Joint training với conversation dataset                   │  │
│  │  Freeze: Base models                                       │  │
│  │  Train: All adapters + fusion layer                        │  │
│  │  LR: 1e-5 (small, avoid catastrophic forgetting)           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 5.2 Evaluation Pipeline

```
┌──────────────────────────────────────────────────────────────────┐
│                    EVALUATION METRICS                            │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Task-Specific Metrics:                                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Fluency:                                                  │  │
│  │  • MAE (Mean Absolute Error): < 0.12                       │  │
│  │  • Pearson r: > 0.90                                       │  │
│  │                                                            │  │
│  │  Vocabulary:                                               │  │
│  │  • Accuracy: > 90%                                         │  │
│  │  • Macro F1: > 0.89                                        │  │
│  │                                                            │  │
│  │  Grammar:                                                  │  │
│  │  • F0.5 Score: > 68                                        │  │
│  │  • Precision: > 78%                                        │  │
│  │                                                            │  │
│  │  Dialogue:                                                 │  │
│  │  • Human evaluation: > 96%                                 │  │
│  │  • Appropriateness: > 94%                                  │  │
│  │  • Pedagogical quality: > 92% (AutoTutor metrics)          │  │
│  │  • Socratic effectiveness: > 88%                           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  System Metrics:                                                 │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  • Total latency: < 500ms (P95)                            │  │
│  │  • Cache hit rate: > 40%                                   │  │
│  │  • Error rate: < 1%                                        │  │
│  │  • Memory usage: < 4GB (mobile), < 8GB (server)            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 6. Performance Metrics

### 6.1 Latency Breakdown

```
┌──────────────────────────────────────────────────────────────────┐
│                    LATENCY BREAKDOWN                             │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Component             │ v1 (Old)  │ v2 (New)  │ Improvement     │
│  ──────────────────────┼───────────┼───────────┼─────────────────│
│  STT (Whisper)         │ N/A       │ 50-100ms  │ Added           │
│  Context Encoder       │ 50ms      │ 15ms      │ -70%            │
│  Qwen (4 adapters)     │ 400-500ms │ -         │ Deprecated      │
│  Qwen (unified)        │ -         │ 100-150ms │ -75%            │
│  LLaMA3-VI             │ Always    │ On-demand │ -100% (often)   │
│  HuBERT (parallel)     │ 100-200ms │ 100-200ms │ Same            │
│  Fusion + Aggregation  │ 50ms      │ 30ms      │ -40%            │
│  TTS (Piper)           │ 100-300ms │ 100-300ms │ Same            │
│  ──────────────────────┼───────────┼───────────┼─────────────────│
│  TOTAL                 │ 800-1000ms│ 300-500ms │ -60%            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 6.2 Resource Requirements

```
┌──────────────────────────────────────────────────────────────────┐
│                    RESOURCE REQUIREMENTS                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Development (Colab T4):                                         │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  GPU VRAM: 15GB available, ~8GB used                       │  │
│  │  • Qwen 4-bit: ~1.5GB                                      │  │
│  │  • Unified adapter: ~80MB                                  │  │
│  │  • HuBERT: ~2GB                                            │  │
│  │  • Whisper: ~1GB                                           │  │
│  │  • Buffer: ~3GB                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Production (Mobile):                                            │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  RAM: 4-6GB                                                │  │
│  │  Storage: ~500MB (models + cache)                          │  │
│  │  • Qwen INT4 GGUF: ~300MB                                  │  │
│  │  • Whisper small: ~150MB                                   │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## 7. AutoTutor Dialogue Strategies

### 7.1 Pedagogical Framework

```
┌──────────────────────────────────────────────────────────────────┐
│              AUTOTUTOR PEDAGOGICAL STRATEGIES                    │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Strategy 1: Socratic Questioning                                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Goal: Guide learner to self-discovery                     │  │
│  │                                                            │  │
│  │  Example:                                                  │  │
│  │  Student: "Yesterday I go to school"                       │  │
│  │  Tutor: "Think about when this happened. What tense        │  │
│  │          describes actions in the past?"                   │  │
│  │  Student: "Past tense?"                                    │  │
│  │  Tutor: "Exactly! So how should we change 'go'?"           │  │
│  │                                                            │  │
│  │  Training Samples: 450 from AutoTutor corpus               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Strategy 2: Scaffolding                                         │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Goal: Break complex tasks into manageable steps           │  │
│  │                                                            │  │
│  │  Example:                                                  │  │
│  │  Student: "I want improve my English"                      │  │
│  │  Tutor: "Good sentence! Let's work on it step by step:     │  │
│  │          1. First, check the verb form after 'want'        │  │
│  │          2. 'Want' needs to be followed by...?"            │  │
│  │  Student: "To improve?"                                    │  │
│  │  Tutor: "Perfect! Now try the full sentence."              │  │
│  │                                                            │  │
│  │  Training Samples: 380 from AutoTutor corpus               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Strategy 3: Positive Feedback with Correction                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Goal: Encourage while teaching                            │  │
│  │                                                            │  │
│  │  Example:                                                  │  │
│  │  Student: "I enjoys reading books"                         │  │
│  │  Tutor: "Great vocabulary choice! 'Reading books' is a     │  │
│  │          wonderful hobby. Quick tip: With 'I', we say      │  │
│  │          'I enjoy' (no 's'). Try it again!"                │  │
│  │                                                            │  │
│  │  Training Samples: 220 from custom ESL corpus              │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Strategy 4: Hint Progression (Progressive Disclosure)           │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Goal: Give increasingly explicit hints                    │  │
│  │                                                            │  │
│  │  Hint Level 1 (Minimal):                                   │  │
│  │    "Check the verb tense"                                  │  │
│  │                                                            │  │
│  │  Hint Level 2 (Moderate):                                  │  │
│  │    "This happened yesterday, so we need past tense"        │  │
│  │                                                            │  │
│  │  Hint Level 3 (Explicit):                                  │  │
│  │    "Change 'go' to 'went' because it's past tense"         │  │
│  │                                                            │  │
│  │  Training Samples: 150 from AutoTutor corpus               │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 7.2 AutoTutor Dataset Processing

```
┌──────────────────────────────────────────────────────────────────┐
│              AUTOTUTOR CORPUS PREPROCESSING                      │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Source: AutoTutor Dialogue Corpus (University of Memphis)       │
│  Original Size: 1,200 tutoring sessions                          │
│  Filtered: 1,200 sessions (100% usable for ESL context)          │
│                                                                  │
│  Extraction Pipeline:                                            │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Step 1: Dialogue Segmentation                             │  │
│  │    • Parse XML/JSON dialogue turns                         │  │
│  │    • Extract tutor-student pairs                           │  │
│  │    • Identify tutoring moves (question, hint, feedback)    │  │
│  │                                                            │  │
│  │  Step 2: Strategy Annotation                               │  │
│  │    • Tag with pedagogical strategy:                        │  │
│  │      - socratic_questioning                                │  │
│  │      - scaffolding                                         │  │
│  │      - positive_feedback                                   │  │
│  │      - hint_giving                                         │  │
│  │      - error_correction                                    │  │
│  │                                                            │  │
│  │  Step 3: Context Enrichment                                │  │
│  │    • Add error types (if grammar correction)               │  │
│  │    • Add learner level (inferred from mistakes)            │  │
│  │    • Add conversation history (3-5 turns)                  │  │
│  │                                                            │  │
│  │  Step 4: Format Conversion                                 │  │
│  │    • Convert to instruction format:                        │  │
│  │      {                                                     │  │
│  │        "instruction": "Act as an English tutor...",        │  │
│  │        "input": "Student: {text}\nContext: {history}",     │  │
│  │        "output": "Tutor: {response}",                      │  │
│  │        "strategy": "socratic_questioning"                  │  │
│  │      }                                                     │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Quality Filtering:                                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  • Remove non-English dialogues                            │  │
│  │  • Remove overly complex academic content                  │  │
│  │  • Keep only ESL-relevant interactions                     │  │
│  │  • Maintain pedagogical diversity (balanced strategies)    │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### 7.3 Tutoring Effectiveness Metrics

```
┌──────────────────────────────────────────────────────────────────┐
│              TUTORING QUALITY EVALUATION                         │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Metric 1: Pedagogical Appropriateness (92% target)              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Criteria:                                                 │  │
│  │  • Uses appropriate tutoring strategy for error type       │  │
│  │  • Adjusts complexity to learner level                     │  │
│  │  • Provides constructive feedback                          │  │
│  │  • Encourages continued learning                           │  │
│  │                                                            │  │
│  │  Evaluation: Human raters (2 ESL teachers)                 │  │
│  │  Scale: 1-5 (≥4 considered appropriate)                    │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Metric 2: Socratic Effectiveness (88% target)                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Criteria:                                                 │  │
│  │  • Guides learner to answer without giving solution        │  │
│  │  • Uses progressive hints (minimal → explicit)             │  │
│  │  • Asks clarifying questions                               │  │
│  │  • Validates learner reasoning                             │  │
│  │                                                            │  │
│  │  Evaluation: A/B testing with learner outcomes             │  │
│  │  Measure: % of learners reaching correct answer            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Metric 3: Learner Engagement (Target: 4.2/5)                    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Criteria:                                                 │  │
│  │  • Response encourages continued conversation              │  │
│  │  • Tone is friendly and supportive                         │  │
│  │  • Provides actionable next steps                          │  │
│  │                                                            │  │
│  │  Evaluation: User surveys + conversation length            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## References

### Language Models

| Model | Paper/Link | Description |
|-------|------------|-------------|
| **Qwen2.5** | [GitHub](https://github.com/QwenLM/Qwen2.5) \| [Paper](https://arxiv.org/abs/2309.16609) | Alibaba's multilingual LLM, strong on English & code |
| **LLaMA 3** | [Meta AI](https://llama.meta.com/) \| [Paper](https://arxiv.org/abs/2407.21783) | Meta's open LLM, excellent for fine-tuning |

### Speech Models

| Model | Paper/Link | Description |
|-------|------------|-------------|
| **Whisper v3** | [OpenAI](https://github.com/openai/whisper) \| [Paper](https://arxiv.org/abs/2212.04356) | SOTA speech recognition, multilingual |
| **Faster-Whisper** | [GitHub](https://github.com/guillaumekln/faster-whisper) | CTranslate2 optimized Whisper (4x faster) |
| **HuBERT** | [Paper](https://arxiv.org/abs/2106.07447) \| [HuggingFace](https://huggingface.co/facebook/hubert-large-ls960-ft) | Self-supervised speech representation |
| **Piper TTS** | [GitHub](https://github.com/rhasspy/piper) | Fast, offline VITS-based TTS |
| **Silero VAD** | [GitHub](https://github.com/snakers4/silero-vad) | Voice Activity Detection |

### Fine-tuning Techniques

| Technique | Paper | Description |
|-----------|-------|-------------|
| **LoRA** | [arXiv:2106.09685](https://arxiv.org/abs/2106.09685) | Low-Rank Adaptation for efficient fine-tuning |
| **QLoRA** | [arXiv:2305.14314](https://arxiv.org/abs/2305.14314) | Quantized LoRA, enables 65B models on single GPU |
| **PEFT** | [GitHub](https://github.com/huggingface/peft) | HuggingFace Parameter-Efficient Fine-Tuning |
| **SFT** | [TRL Docs](https://huggingface.co/docs/trl/sft_trainer) | Supervised Fine-Tuning Trainer |

### Datasets

#### Grammar Error Correction (GEC)

| Dataset | Link | Size | Description |
|---------|------|------|-------------|
| **BEA-2019** | [CodaLab](https://www.cl.cam.ac.uk/research/nl/bea2019st/) | 34K sentences | Write & Improve + LOCNESS shared task |
| **FCE Corpus** | [Cambridge](https://ilexir.co.uk/datasets/index.html) | 1,244 scripts | First Certificate in English exam |
| **CoNLL-2014** | [NUS](https://www.comp.nus.edu.sg/~nlp/conll14st.html) | 1,312 essays | Grammatical Error Correction shared task |
| **JFLEG** | [GitHub](https://github.com/keisks/jfleg) | 1,501 sentences | Fluency-focused GEC benchmark |
| **W&I+LOCNESS** | [HuggingFace](https://huggingface.co/datasets/wi_locness) | 34K | Combined Write&Improve + LOCNESS |
| **ERRANT** | [GitHub](https://github.com/chrisjbryant/errant) | Tool | Error annotation toolkit |

#### English Learner Corpora

| Dataset | Link | Size | Description |
|---------|------|------|-------------|
| **EFCAMDAT** | [EF-Cambridge](https://corpus.mml.cam.ac.uk/efcamdat/) | 83M words | EF-Cambridge Open Language Database, CEFR-labeled |
| **TOEFL11** | [ETS](https://www.ets.org/research/policy_research_reports/publications/report/2013/jngi.html) | 12,100 essays | TOEFL essays with scores |
| **ICNALE** | [Official](https://language.sakura.ne.jp/icnale/) | 10K essays | International Corpus Network of Asian Learners |
| **PELIC** | [GitHub](https://github.com/ELI-Data-Mining-Group/PELIC-dataset) | 46K texts | Pitt English Language Institute Corpus |

#### CEFR & Vocabulary

| Dataset | Link | Description |
|---------|------|-------------|
| **CEFR-J Wordlist** | [Official](https://www.cefr-j.org/download.html) | Japanese CEFR word frequency lists |
| **English Profile** | [Cambridge](https://www.englishprofile.org/wordlists) | Official CEFR vocabulary lists |
| **Oxford 3000/5000** | [Oxford](https://www.oxfordlearnersdictionaries.com/wordlists/oxford3000-5000) | Core vocabulary lists |
| **EVP (English Vocab Profile)** | [Cambridge](https://www.englishprofile.org/wordlists/evp) | CEFR-graded vocabulary |

#### Dialogue & Conversation

| Dataset | Link | Size | Description |
|---------|------|------|-------------|
| **Intel/orca_dpo_pairs** | [HuggingFace](https://huggingface.co/datasets/Intel/orca_dpo_pairs) | 13K | DPO training pairs |
| **Anthropic HH-RLHF** | [HuggingFace](https://huggingface.co/datasets/Anthropic/hh-rlhf) | 170K | Human preference data |
| **OpenAssistant** | [HuggingFace](https://huggingface.co/datasets/OpenAssistant/oasst1) | 161K | Multilingual conversation |
| **Tatoeba** | [Official](https://tatoeba.org/en/downloads) | 10M+ | Parallel sentences, good for translation |

#### Pronunciation & Speech

| Dataset | Link | Size | Description |
|---------|------|------|-------------|
| **TIMIT** | [LDC](https://catalog.ldc.upenn.edu/LDC93s1) | 6,300 utterances | Phoneme-aligned speech corpus |
| **LibriSpeech** | [OpenSLR](https://www.openslr.org/12/) | 1,000 hours | Clean speech for ASR |
| **CommonVoice** | [Mozilla](https://commonvoice.mozilla.org/en/datasets) | 17K+ hours | Multilingual speech corpus |
| **L2-ARCTIC** | [GitHub](https://psi.engr.tamu.edu/l2-arctic-corpus/) | 26 hours | Non-native English speech |

### Related Research Papers

#### Grammar Error Correction

| Paper | Year | Link | Key Contribution |
|-------|------|------|------------------|
| GECToR | 2020 | [arXiv:2005.12592](https://arxiv.org/abs/2005.12592) | Efficient sequence tagging for GEC |
| T5 for GEC | 2021 | [ACL](https://aclanthology.org/2021.bea-1.4/) | Transfer learning approach |
| GrammarT5 | 2022 | [arXiv:2203.07442](https://arxiv.org/abs/2203.07442) | Grammar pre-training |
| LLM-GEC | 2023 | [arXiv:2303.13648](https://arxiv.org/abs/2303.13648) | LLMs for GEC |

#### Language Assessment

| Paper | Year | Link | Key Contribution |
|-------|------|------|------------------|
| CEFR Classification | 2018 | [ACL](https://aclanthology.org/W18-3701/) | Automatic CEFR level prediction |
| Automated Essay Scoring | 2020 | [arXiv:2012.13958](https://arxiv.org/abs/2012.13958) | BERT for essay scoring |
| Fluency Assessment | 2021 | [Interspeech](https://www.isca-speech.org/archive/interspeech_2021/) | Speech fluency metrics |

#### Multi-task Learning

| Paper | Year | Link | Key Contribution |
|-------|------|------|------------------|
| Multi-Task Deep Neural Networks | 2019 | [arXiv:1901.11504](https://arxiv.org/abs/1901.11504) | MT-DNN framework |
| Unified Language Model | 2020 | [NeurIPS](https://proceedings.neurips.cc/paper/2020) | UniLM pre-training |
| T5 | 2020 | [arXiv:1910.10683](https://arxiv.org/abs/1910.10683) | Text-to-Text Transfer Transformer |

### Tools & Libraries

| Tool | Link | Purpose |
|------|------|---------|
| **Transformers** | [HuggingFace](https://github.com/huggingface/transformers) | Model loading & inference |
| **PEFT** | [HuggingFace](https://github.com/huggingface/peft) | Parameter-efficient fine-tuning |
| **TRL** | [HuggingFace](https://github.com/huggingface/trl) | Transformer Reinforcement Learning |
| **BitsAndBytes** | [GitHub](https://github.com/TimDettmers/bitsandbytes) | 8-bit/4-bit quantization |
| **vLLM** | [GitHub](https://github.com/vllm-project/vllm) | High-throughput LLM serving |
| **ERRANT** | [GitHub](https://github.com/chrisjbryant/errant) | Error annotation toolkit |
| **Language Tool** | [GitHub](https://github.com/languagetool-org/languagetool) | Rule-based grammar checking |
| **Sentence-Transformers** | [GitHub](https://github.com/UKPLab/sentence-transformers) | Sentence embeddings |

### Vietnamese NLP Resources

| Resource | Link | Description |
|----------|------|-------------|
| **VinAI PhoGPT** | [GitHub](https://github.com/VinAIResearch/PhoGPT) | Vietnamese generative model |
| **VietAI ViT5** | [HuggingFace](https://huggingface.co/VietAI/vit5-base) | Vietnamese T5 |
| **UIT-ViNewsQA** | [GitHub](https://github.com/xmen-ai/Vietnamese-QA) | Vietnamese QA dataset |
| **VLSP** | [Official](https://vlsp.org.vn/) | Vietnamese Language and Speech Processing |

### Mobile Deployment

| Resource | Link | Description |
|----------|------|-------------|
| **ONNX Runtime** | [GitHub](https://github.com/microsoft/onnxruntime) | Cross-platform inference |
| **TensorFlow Lite** | [TensorFlow](https://www.tensorflow.org/lite) | Mobile deployment |
| **llama.cpp** | [GitHub](https://github.com/ggerganov/llama.cpp) | CPU inference for LLMs |
| **whisper.cpp** | [GitHub](https://github.com/ggerganov/whisper.cpp) | CPU inference for Whisper |
| **MLC LLM** | [GitHub](https://github.com/mlc-ai/mlc-llm) | Universal LLM deployment |

---

## Quick Download Links

### Models (HuggingFace)

```bash
# Qwen3-1.7B
huggingface-cli download Qwen/Qwen3-1.7B

# Whisper Small (for production)
huggingface-cli download openai/whisper-small

# HuBERT Large
huggingface-cli download facebook/hubert-large-ls960-ft

# Sentence Transformer
huggingface-cli download sentence-transformers/all-MiniLM-L6-v2
```

### Datasets (HuggingFace)

```python
from datasets import load_dataset

# Grammar Error Correction
bea2019 = load_dataset("wi_locness")
jfleg = load_dataset("jfleg")

# Dialogue
orca = load_dataset("Intel/orca_dpo_pairs")

# Parallel Sentences
tatoeba = load_dataset("tatoeba", lang1="en", lang2="vi")

# Speech (for pronunciation)
common_voice = load_dataset("mozilla-foundation/common_voice_13_0", "en")
```

---

> **Document Version**: 5.2
> **Last Updated**: January 2026
> **Author**: Nguyen Huu Thang