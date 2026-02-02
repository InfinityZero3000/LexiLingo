
# LexiLingo AI Architecture v4.0 - LangGraph + GraphCAG

> **Document**: Kiến trúc hệ thống AI cho ứng dụng học tiếng Anh  
> **Version**: 4.0 (LangGraph + GraphCAG Hybrid)  
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
│                                                                 │
│  LAYER 1: LangGraph (Orchestration + Observer)                  │
│  ─────────────────────────────────────────────                  │
│  ✓ StateGraph: Typed state machine for conversation flow        │
│  ✓ Observer: Track errors → Update KG → Queue background jobs   │
│  ✓ Checkpointing: Resumable sessions, persistence               │
│  ✓ Async Background: Exercise generation without blocking       │
│                                                                 │
│  LAYER 2: GraphCAG (Core AI Pipeline)                           │
│  ─────────────────────────────────────                          │
│  ✓ KG (KuzuDB): Concept expansion, mastery tracking             │
│  ✓ CAG (Redis): Cache-Augmented Generation, response patterns   │
│  ✓ Rule-first: Grammar check rule-based, LLM as fallback        │
│  ✓ Ultra-low latency: <10ms cache hit, <180ms cache miss        │
│                                                                 │
│  LAYER 3: AI Models                                             │
│  ──────────────────                                             │
│  ✓ Qwen3-1.7B: English NLP (grammar, dialogue, analysis)        │
│  ✓ LLaMA3-3B: Vietnamese explanations (lazy loaded)             │
│  ✓ HuBERT: Pronunciation analysis (lazy loaded)                 │
│  ✓ Piper: Text-to-Speech                                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 Tech Stack

| Component | Technology | Size | Latency |
|-----------|------------|------|---------|
| **Orchestration** | **LangGraph** | **-** | **<5ms** |
| STT | Faster-Whisper v3 | 244MB | 50-100ms |
| Context Encoder | all-MiniLM-L6-v2 | 22MB | 15ms |
| NLP (English) | **Qwen3-1.7B** + Unified LoRA | 1.7GB + 80MB | 100-150ms |
| NLP (Vietnamese) | **LLaMA3-3B** (Q4, lazy) | 4GB | 200-500ms |
| Knowledge Graph | KuzuDB | <50MB | <5ms |
| Pronunciation | HuBERT-large (lazy) | 2GB | 100-200ms |
| TTS | Piper VITS | 30-60MB | 100-300ms |
| Cache (CAG) | Redis | - | <5ms |
| **Logging DB** | **MongoDB** | **-** | **<10ms** |

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
│                    STT: FASTER-WHISPER v3                        │
├──────────────────────────────────────────────────────────────────┤
│  Model: openai/whisper-small (244MB) + CTranslate2 optimization  │
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
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  MongoDB: AI Learning Logs (Persistent Storage)            │  │
│  │  • Collections:                                            │  │
│  │    - ai_interactions: Full interaction logs + feedback     │  │
│  │    - model_metrics: Performance tracking over time         │  │
│  │    - learning_patterns: Aggregated user error patterns     │  │
│  │    - training_queue: Curated examples for LoRA tuning      │  │
│  │  • Environment:                                            │  │
│  │    - Dev: Docker local (mongodb://localhost:27017)         │  │
│  │    - Prod: Atlas FREE (mongodb+srv://...)                  │  │
│  │  • Auto-cleanup: TTL indexes (90 days retention)           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
        │
        │ Context Vector + Learner Profile
        ▼
┌──────────────────────────────────────────────────────────────────┐
│         LANGGRAPH + GRAPHCAG HYBRID ARCHITECTURE                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │            LANGGRAPH LAYER (Orchestration)                 │  │
│  ├────────────────────────────────────────────────────────────┤  │
│  │                                                            │  │
│  │  StateGraph: Typed state machine for conversation flow     │  │
│  │                                                            │  │
│  │  Responsibilities:                                         │  │
│  │  • Track conversation state across turns                   │  │
│  │  • Route to appropriate pipeline nodes                     │  │
│  │  • Trigger Observer for error tracking (async)             │  │
│  │  • Enable checkpointing for session persistence            │  │
│  │                                                            │  │
│  │  Observer Pattern (async, non-blocking):                   │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │ 1. Qwen detects errors (verb_tense, articles, etc)   │  │  │
│  │  │ 2. Observer logs errors to KG (update mastery)       │  │  │
│  │  │ 3. Queue background jobs for CAG exercise gen        │  │  │
│  │  │ 4. Next session: personalized exercises ready        │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                              │                                   │
│                              ▼                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │            GRAPHCAG LAYER (Core AI Pipeline)               │  │
│  ├────────────────────────────────────────────────────────────┤  │
│  │                                                            │  │
│  │  GraphCAG = KG + Cache-Augmented Generation                │  │
│  │  Ultra-low latency (<50ms) for real-time tutoring          │  │
│  │                                                            │  │
│  │  Core Principle:                                           │  │
│  │  • Pre-cache KG knowledge into LLM KV Cache                │  │
│  │  • Avoid retrieval on every query → reduce latency         │  │
│  │  • Rule-first, LLM-fallback → predictable performance      │  │
│  │                                                            │  │
│  │  Technology:                                               │  │
│  │  • KuzuDB: Concept relationships, prerequisites            │  │
│  │  • Redis: Cache layer, learner profiles, responses         │  │
│  │  • Qwen3: Generation with pre-cached context               │  │
│  │                                                            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Architecture Comparison:                                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ RAG:     Query → Retrieve → Augment → Generate (200-500ms) │  │
│  │ GraphCAG: Pre-cache → Query → Generate (<50ms) ⚡           │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Pipeline Flow:                                                  │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                                                             │ │
│  │  ┌─────────────────────────────────────────────────────┐    │ │
│  │  │         PHASE 1: WARM-UP (On Session Start)         │    │ │
│  │  │                                                     │    │ │
│  │  │  Load learner profile → Query KG prerequisites      │    │ │
│  │  │  → Pre-cache concepts into LLM KV Cache             │    │ │
│  │  │                                                     │    │ │
│  │  │  ┌──────────┐   ┌──────────┐   ┌──────────────┐     │    │ │
│  │  │  │  Redis   │──▶│  KuzuDB  │──▶│  LLM Cache   │     │    │ │
│  │  │  │(Profile) │   │ (KG)     │   │ (KV Warmup)  │     │    │ │
│  │  │  └──────────┘   └──────────┘   └──────────────┘     │    │ │
│  │  │                                                     │    │ │
│  │  └─────────────────────────────────────────────────────┘    │ │
│  │                          │                                  │ │
│  │                          ▼                                  │ │
│  │  ┌─────────────────────────────────────────────────────┐    │ │
│  │  │         PHASE 2: QUERY (Per User Message)           │    │ │
│  │  │                                                     │    │ │
│  │  │  User Input                                         │    │ │
│  │  │      │                                              │    │ │
│  │  │      ▼                                              │    │ │
│  │  │  ┌──────────────┐                                   │    │ │
│  │  │  │ Cache Lookup │◄── Redis: Check cached response   │    │ │
│  │  │  └──────┬───────┘                                   │    │ │
│  │  │         │                                           │    │ │
│  │  │    ┌────┴────┐                                      │    │ │
│  │  │    │Cache Hit?│                                     │    │ │
│  │  │    └────┬────┘                                      │    │ │
│  │  │    Yes  │  No                                       │    │ │
│  │  │     │   └──────────────────────┐                    │    │ │
│  │  │     ▼                          ▼                    │    │ │
│  │  │  ┌────────┐            ┌──────────────┐             │    │ │
│  │  │  │ Return │            │ KG Expansion │             │    │ │
│  │  │  │ Cached │            │ (Linked      │             │    │ │
│  │  │  │Response│            │  Concepts)   │             │    │ │
│  │  │  └────────┘            └──────┬───────┘             │    │ │
│  │  │      ▲                       │                      │    │ │
│  │  │      │                       ▼                      │    │ │
│  │  │      │                ┌──────────────┐              │    │ │
│  │  │      │                │  Diagnose    │              │    │ │
│  │  │      │                │ (Rule-based) │              │    │ │
│  │  │      │                └──────┬───────┘              │    │ │
│  │  │      │                       │                      │    │ │
│  │  │      │                       ▼                      │    │ │
│  │  │      │                ┌──────────────┐              │    │ │
│  │  │      │                │   Generate   │              │    │ │
│  │  │      │                │ (LLM/Rules)  │              │    │ │
│  │  │      │                └──────┬───────┘              │    │ │
│  │  │      │                       │                      │    │ │
│  │  │      │                       ▼                      │    │ │
│  │  │      │                ┌──────────────┐              │    │ │
│  │  │      └────────────────│ Cache Update │              │    │ │
│  │  │                       └──────────────┘              │    │ │
│  │  │                                                     │    │ │
│  │  └─────────────────────────────────────────────────────┘    │ │
│  │                                                             │ │
│  └─────────────────────────────────────────────────────────────┘ │
│                                                                  │
│  Component Details:                                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Cache Lookup  : Redis query for similar input patterns     │  │
│  │ KG Expansion  : KuzuDB graph traversal (1-2 hops)          │  │
│  │ Diagnose      : Rule-based grammar check → concept mapping │  │
│  │ Generate      : LLM with KV-cached context (fast)          │  │
│  │ Cache Update  : Store response pattern for future use      │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Latency Breakdown:                                              │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │ Component        │ Cache Hit │ Cache Miss │                │  │
│  │──────────────────┼───────────┼────────────│                │  │
│  │ Redis Lookup     │   <5ms    │    <5ms    │                │  │
│  │ KG Expansion     │   skip    │   <10ms    │                │  │
│  │ Diagnose         │   skip    │   <10ms    │                │  │
│  │ LLM Generate     │   skip    │  100-150ms │                │  │
│  │ Cache Update     │   skip    │    <5ms    │                │  │
│  │──────────────────┼───────────┼────────────│                │  │
│  │ TOTAL            │  <10ms ⚡  │  <180ms    │                │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Background Observer (LangGraph, async):                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  1. Track detected errors from Diagnose step              │  │
│  │  2. Update mastery scores in KG (async)                   │  │
│  │  3. Queue background jobs for CAG exercise generation     │  │
│  │  4. Next session: personalized exercises ready            │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
        │
        │
   ┌────┴────────────────────────────────────────┐
   │                                             │
   ▼                                             ▼
┌─────────────────────────────┐    ┌─────────────────────────────┐
│   PRIMARY: Qwen2.5-1.5B     │    │   PARALLEL: HuBERT-large    │
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
                             ↺ (conversation loop)
```

---

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

### 3.2 LangGraph + GraphCAG Pipeline

> **Note**: The old `AIOrchestrator` class has been replaced by the LangGraph + GraphCAG hybrid architecture.
> See `api/services/graph_cag/` for the new implementation.

```
┌──────────────────────────────────────────────────────────────────┐
│              LANGGRAPH + GRAPHCAG PIPELINE                       │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Implementation: api/services/graph_cag/                         │
│                                                                  │
│  Files:                                                          │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  graph.py    : StateGraph definition, compiled pipeline    │  │
│  │  nodes.py    : Node functions (diagnose, generate, etc)    │  │
│  │  edges.py    : Routing logic (cache hit/miss, VI needed)   │  │
│  │  state.py    : TypedDict schema for state management       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Key Advantages over old AIOrchestrator:                         │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Ultra-low latency (<50ms cache hit)                       │  │
│  │  Built-in checkpointing (LangGraph)                        │  │
│  │  Async Observer pattern (non-blocking)                     │  │
│  │  Typed state management (TypedDict)                        │  │
│  │  KG-integrated (KuzuDB concepts)                           │  │
│  │  Cache-augmented (Redis response patterns)                 │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Performance Comparison:                                         │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Metric            │ Old Orchestrator │ LangGraph+GraphCAG │  │
│  │  ──────────────────┼──────────────────┼────────────────────│  │
│  │  Cache Hit Latency │ N/A              │ <10ms ⚡            │  │
│  │  Cache Miss Latency│ 350ms            │ <180ms             │  │
│  │  State Persistence │ Manual           │ Built-in           │  │
│  │  Error Tracking    │ Logged only      │ KG-integrated      │  │
│  │  Exercise Gen      │ N/A              │ Background CAG     │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```


### 3.3 Caching Architecture

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
│  │  Key: response:{text_hash}                                 │  │
│  │  Value: { "analysis": {...}, "audio_url": "..." }          │  │
│  │  TTL: 7 days                                               │  │
│  │  Hit rate target: >40%                                     │  │
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
│              UNIFIED LoRA ADAPTER (Qwen2.5-1.5B)                 │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Configuration:                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Base Model: Qwen/Qwen2.5-1.5B-Instruct                    │  │
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
│  │  • Base: Qwen2.5-1.5B-Instruct (4-bit quantized)           │  │
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
# Qwen2.5-1.5B-Instruct
huggingface-cli download Qwen/Qwen2.5-1.5B-Instruct

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

> **Document Version**: 4.0 (LangGraph + GraphCAG Hybrid)  
> **Last Updated**: January 2026  
> **Author**: Nguyen Huu Thang  