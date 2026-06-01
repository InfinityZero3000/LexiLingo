# 🎯 LexiLingo MVP Architecture (Simplified)

> **Optimized for rapid deployment, cost-effectiveness, and scalability**

---

## 📊 Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT LAYER                            │
│  (Flutter App - Mobile/Web/Desktop)                             │
└────────────┬────────────────────────────────────┬───────────────┘
             │                                    │
    ┌────────▼────────┐                  ┌───────▼────────┐
    │ Backend Service │                  │  AI Service    │
    │   (Port 8000)   │                  │  (Port 8001)   │
    │                 │                  │                │
    │ ┌─────────────┐ │                  │ ┌────────────┐ │
    │ │ PostgreSQL  │ │                  │ │  MongoDB   │ │
    │ │ (Users,     │ │                  │ │ (Sessions, │ │
    │ │  Courses,   │ │                  │ │  AI Data)  │ │
    │ │  Progress)  │ │                  │ └────────────┘ │
    │ └─────────────┘ │                  │                │
    │                 │                  │ ┌────────────┐ │
    │ FastAPI         │◄─────────────────┤ │   Redis    │ │
    │ JWT Auth        │   Shared Auth    │ │  (Cache)   │ │
    └─────────────────┘                  │ └────────────┘ │
                                         │                │
                                         │ AI PIPELINE:   │
                                         │                │
                                         │ 1. STT ──────┐ │
                                         │    Whisper   │ │
                                         │    244MB     │ │
                                         │              │ │
                                         │ 2. NLP ◄─────┤ │
                                         │    Qwen      │ │
                                         │    900MB(Q4) │ │
                                         │              │ │
                                         │ 3. KG ◄──────┤ │
                                         │    NetworkX  │ │
                                         │    50MB      │ │
                                         │              │ │
                                         │ 4. TTS ◄─────┘ │
                                         │    Piper     │ │
                                         │    63MB      │ │
                                         └────────────────┘
```

---

## 💾 Memory Footprint

### Total Memory: **2.4GB** (fits in 4GB server)

| Component | Size (Disk) | RAM (Loaded) | When Loaded |
|-----------|-------------|--------------|-------------|
| **Faster-Whisper v3** | 244MB | 500MB | On voice input |
| **Qwen3-1.7B-Q4** | 900MB | 1200MB | Always |
| **Piper TTS** | 63MB | 200MB | On response gen |
| **Knowledge Graph** | 50MB | 100MB | Always |
| **Redis Cache** | - | 200MB | Always |
| **CAG Pre-generated** | 100MB | 100MB | On-demand |
| **Python Runtime** | - | 1000MB | Always |
| **TOTAL (Peak)** | ~1.4GB | ~3.3GB | Worst case |
| **TOTAL (Normal)** | ~1.4GB | ~2.6GB | Typical |
| **TOTAL (Baseline)** | ~1.4GB | ~1.6GB | Text-only |

**Optimization:** Lazy loading → 1.6GB baseline

---

## ⚡ Performance Targets

### Latency Breakdown (per request)

```
Voice Input Flow:
├── User speaks (2s)
├── STT transcription: 50ms
├── Context lookup (Redis): 10ms
├── Qwen inference: 200ms
├── KG query: 5ms
├── TTS generation: 150ms
└── Total: 415ms → User hears response in <0.5s ✅

Text Input Flow:
├── User types
├── Context lookup: 10ms
├── Qwen inference: 200ms
├── KG query: 5ms
└── Total: 215ms → Fast response ✅
```

**Target:** <500ms total latency (excellent UX)

---

## 🏗️ Technology Stack (Simplified)

### AI Components (No fine-tuning where not needed)

```yaml
Speech:
  STT: 
    - Model: Faster-Whisper v3 Base
    - Size: 244MB
    - Fine-tuned: ❌ No (pre-trained is good enough)
    - Accuracy: 95%+ on clear English
  
  TTS:
    - Model: Piper VITS (en_US-lessac-medium)
    - Size: 63MB
    - Fine-tuned: ❌ No (natural voice out-of-box)
    - Quality: Near-human

NLP:
  Core:
    - Model: Qwen3-1.7B
    - Quantization: Q4_K_M (4-bit)
    - Fine-tuned: ✅ Yes (4 LoRA adapters)
      - Grammar correction
      - Vocabulary classification
      - Fluency scoring
      - Dialogue generation
    - Size: 900MB (down from 3GB)
    - Accuracy: 98% of float16

Knowledge:
  Graph:
    - Library: NetworkX (Python)
    - Nodes: 15K (words, rules, concepts)
    - Edges: 30K (relationships)
    - Size: 50MB in-memory
    - Query: <5ms (hashtable)
  
  CAG:
    - Pre-generated: 1000 lessons, 5000 exercises
    - Size: 100MB
    - Generation: Background async
  
  Cache:
    - Redis: 200MB
    - Hit rate: 40-50%
    - TTL: 7 days

Fallbacks (Cloud APIs):
  Vietnamese:
    - Primary: Google Translate API (free tier)
    - Backup: Gemini API
  
  Pronunciation:
    - Azure Speech API (free tier: 5hrs/mo)
    - Google Cloud Speech
```

---

## 💰 Cost Breakdown

### Monthly Operating Costs

| Item | Details | Cost/mo |
|------|---------|---------|
| **Server (Railway)** | 4GB RAM, 2 vCPU | $20 |
| **PostgreSQL** | Included in server | $0 |
| **MongoDB** | Included in server | $0 |
| **Redis** | Included in server | $0 |
| **Google Translate API** | 500K chars free/mo | $0-5 |
| **Azure Speech** | 5hrs free/mo | $0-5 |
| **Domain + SSL** | Cloudflare (free) | $0 |
| **CDN** | Cloudflare (free) | $0 |
| **TOTAL MVP** | | **$20-30** |

**Scale costs (if 1000+ users):**
- Upgrade to 8GB server: +$28/mo
- Cloud APIs: +$20-50/mo
- Total: $68-108/mo (still affordable)

---

## 📈 Comparison: Full vs Simplified

| Metric | Full Architecture | **Simplified (MVP)** | Savings |
|--------|-------------------|----------------------|---------|
| Memory | 8.5GB | **2.4GB** | **72%** ↓ |
| Server | $48-150/mo | **$20-30/mo** | **75%** ↓ |
| Setup Time | 2-3 months | **3-4 weeks** | **60%** ↓ |
| Latency | 350ms | 500ms | 43% ↑ (acceptable) |
| Quality | 100% | 95% | 5% ↓ (acceptable) |
| Offline | Partial | No | Trade-off |

**Winner:** Simplified for MVP! 🏆

---

## 🚀 Deployment Strategy

### Phase 1: MVP (Weeks 1-8)

```bash
Week 1-2: Infrastructure
├── Setup Railway/DigitalOcean
├── Deploy PostgreSQL + MongoDB + Redis
├── Configure Docker Compose
└── CI/CD with GitHub Actions

Week 3-4: Core AI
├── Deploy Qwen quantized model
├── Integrate Faster-Whisper
├── Integrate Piper TTS
└── Test end-to-end pipeline

Week 5-6: Knowledge Layer
├── Build Knowledge Graph
├── Implement CAG
├── Setup Redis caching
└── Cloud API fallbacks

Week 7-8: Integration & Polish
├── Flutter app integration
├── Performance tuning
├── Load testing
└── MVP Launch! 🎉
```

### Phase 2: Scale (Months 3-6, if needed)

```bash
Add when >1000 users:
├── 8GB server upgrade
├── Add LLaMA3-VI (if Vietnamese critical)
├── Add HuBERT (if pronunciation critical)
├── Load balancer (handle 500+ concurrent)
└── Monitoring (Prometheus + Grafana)
```

---

## 🎯 Why This Architecture Works

### ✅ Advantages

1. **Cost-Effective**
   - $20-30/mo total for MVP
   - No expensive GPU needed
   - Free tier APIs for fallbacks

2. **Fast Deployment**
   - No complex model training needed (STT/TTS)
   - Only fine-tune core NLP
   - Standard Docker deployment

3. **Good Performance**
   - <500ms latency (excellent UX)
   - 95%+ accuracy (production-ready)
   - Handles 50-100 concurrent users

4. **Scalable**
   - Easy to upgrade server
   - Can add components later
   - Horizontal scaling possible

5. **Maintainable**
   - Simple architecture
   - Well-documented components
   - Standard tech stack

### ⚠️ Trade-offs (Acceptable for MVP)

1. **No Offline Mode**
   - Needs internet connection
   - Mitigated: Cache common responses

2. **Higher Latency than Full**
   - 500ms vs 350ms
   - Still feels instant (<1s)

3. **API Dependency**
   - Vietnamese translation
   - Pronunciation analysis
   - Mitigated: Free tiers sufficient

4. **Limited Concurrency**
   - 50-100 users initially
   - Upgrade path clear

---

## 🔒 Security Considerations

```yaml
Authentication:
  - JWT tokens (shared secret)
  - Password hashing (bcrypt)
  - Rate limiting (10 req/min/user)

Data Protection:
  - HTTPS only
  - Database encryption at rest
  - Redis password protected
  - No sensitive data in logs

API Security:
  - API keys in environment variables
  - Rotate keys monthly
  - Monitor usage

Privacy:
  - User data consent
  - GDPR compliance ready
  - Data deletion on request
```

---

## 📊 Monitoring & Metrics

```yaml
Track:
  Performance:
    - Latency (p50, p95, p99)
    - Throughput (req/sec)
    - Error rate

  Resources:
    - CPU usage
    - Memory usage
    - Disk usage
    - Network I/O

  Business:
    - Active users
    - Sessions/day
    - API costs
    - Cache hit rate

Tools:
  - Prometheus (metrics)
  - Grafana (dashboards)
  - Sentry (error tracking)
  - Railway logs
```

---

## ✅ Final Verdict

**Architecture đơn giản hóa này:**

```
✅ Hoàn toàn khả thi cho production MVP
✅ Cost-effective ($20-30/mo)
✅ Fast deployment (6-8 weeks)
✅ Good performance (<500ms)
✅ Scalable khi cần

Recommended: YES! 🎯
```

**Next steps:**
1. Setup server infrastructure
2. Deploy quantized Qwen model
3. Integrate STT/TTS
4. Build KG + CAG
5. Launch MVP! 🚀

---

**Document version:** 1.0  
**Last updated:** 2026-01-24  
**Author:** LexiLingo Team

