# TRACE-CAG Portable Service Guide

This document explains how to use the packaged TRACE-CAG service and the theory
behind its reusable cache-aware generation mechanism.

## 1. Purpose

The goal of `service/tracecag_service` is to turn TRACE-CAG from an app-local
pipeline into a reusable service contract. A new project should be able to:

1. import `TraceCAGRequest`, `TraceCAGResponse`, and `TraceCAGService`;
2. provide an analyzer adapter for its own KG/cache/LLM stack;
3. keep the core TRACE-CAG ideas: state fingerprinting, cache safety, graph-aware
   near-hit reuse, and conservative fallback;
4. avoid importing LexiLingo FastAPI modules unless it explicitly chooses the
   LexiLingo adapter.

This package is intentionally additive. It does not move or rename the current
`api/services/trace_cag` implementation.

## 2. High-Level Architecture

```text
Caller
  |
  v
TraceCAGRequest
  |
  v
TraceCAGService
  |-- validation
  |-- timeout
  |-- batch concurrency
  |-- response normalization
  |
  v
TraceCAGAnalyzer adapter
  |-- LexiLingo adapter: current production pipeline
  |-- Memory adapter: dependency-free L0/L1 demo
  |-- Custom adapter: any project-specific implementation
  |
  v
TraceCAGResponse
```

The important design decision is the `TraceCAGAnalyzer` port:

```python
async def analyze(request: TraceCAGRequest) -> TraceCAGResponse | dict:
    ...
```

Everything else is replaceable. One project can use LangGraph; another can use
a simple function; another can call an external HTTP service. The caller still
sees the same request and response contract.

## 3. Package Boundaries

| Layer | Files | Responsibility |
| --- | --- | --- |
| Contract | `schemas.py` | Stable request and response DTOs. |
| Runtime | `runtime.py`, `config.py` | Service facade, validation, timeout, batch execution. |
| Port | `ports.py` | Protocol that adapters implement. |
| Core mechanism | `core/fingerprint.py`, `core/scar_l1.py` | Pure cache-state logic. |
| Adapters | `adapters/lexilingo.py`, `adapters/memory.py` | Bind the contract to a concrete implementation. |

Top-level package imports should stay lightweight. The only `api.*` import is
inside `LexiLingoTraceCAGAnalyzer._get_pipeline()`, so importing the portable
package in another project does not boot the LexiLingo app.

## 4. Usage In LexiLingo

Use this when you want the new service contract but still want the existing
pipeline implementation:

```python
from service.tracecag_service import TraceCAGRequest
from service.tracecag_service.adapters.lexilingo import create_lexilingo_service

service = create_lexilingo_service()

response = await service.analyze(
    TraceCAGRequest(
        user_input="I go to school yesterday.",
        session_id="lexi-session-1",
        user_id="user-1",
        input_type="text",
        learner_profile={"level": "B1"},
    )
)
```

What happens:

1. `TraceCAGService` validates the request.
2. `LexiLingoTraceCAGAnalyzer` lazily loads `get_trace_cag()`.
3. `TraceCAGRequest.to_pipeline_kwargs()` maps the portable DTO to the current
   `TraceCAGPipeline.analyze(...)` signature.
4. The existing production pipeline runs.
5. The result is normalized into `TraceCAGResponse`.

## 5. Usage In A New Project

Start with a custom analyzer:

```python
from service.tracecag_service import TraceCAGRequest, TraceCAGResponse, TraceCAGService


class ProjectAnalyzer:
    async def analyze(self, request: TraceCAGRequest) -> TraceCAGResponse:
        profile = request.learner_profile or {"level": "B1"}
        return TraceCAGResponse(
            tutor_response=f"Project answer for {profile['level']}: {request.user_input}",
            metadata={"path": "slow", "cache_hit": False},
        )


service = TraceCAGService(ProjectAnalyzer())
response = await service.analyze_text("Explain present perfect", session_id="demo")
```

Then incrementally replace the placeholder with:

1. a real profile/history store;
2. a KG or document retriever;
3. a cache store;
4. an LLM generator;
5. the pure fingerprint and SCAR-L1 logic from `core/`.

## 6. TRACE-CAG Mechanism

TRACE-CAG is a cache-aware generation strategy. Its central question is:

> Can this request reuse an existing response artifact without violating user,
> profile, graph, evidence, or task state?

The answer is ternary:

| Decision | Meaning | Cost profile |
| --- | --- | --- |
| `reuse` | Cached response is state-compatible and can be returned directly. | Lowest latency/cost. |
| `patch` | Cached artifact is near enough, but the caller should apply a small adaptation. | Low latency/cost. |
| `full` | Cache is unsafe or unavailable; run full retrieval/generation. | Highest latency/cost, safest fallback. |

The portable package currently exposes two core mechanisms:

- fingerprinting: convert request/profile/history into stable state features;
- SCAR-L1: decide whether a graph-bucket near-hit is safe to reuse or patch.

## 7. State Fingerprinting

`core/fingerprint.py` builds `TraceCAGFingerprint`:

```text
TraceCAGFingerprint
  query_norm        normalized text
  intent            correct | explain | practice | ask
  level             A1..C2, default B1
  profile_epoch     hash of coarse learner profile state
  session_turn      conversation history length
  concepts          grammar/topic/entity hints
  entities          stable entity-like tokens
  answer_target     feedback | person | place | time | number | entity
  relation_hints    founder | author | location | comparison | ...
```

The fingerprint serves two jobs:

1. Build an L0 exact cache key with `build_cache_key(fingerprint)`.
2. Build an L1 graph-state bucket with `build_graph_bucket(fingerprint)`.

Why not cache only by normalized text? Because two identical-looking questions
can be unsafe to reuse across learner level, profile progress, task intent, or
graph/evidence state.

## 8. L0 Exact Reuse

L0 is the fastest path. The memory adapter computes:

```python
fingerprint = build_fingerprint(...)
cache_key = build_cache_key(fingerprint)
```

If the exact key exists and the entry is not stale, the adapter returns:

```text
metadata.cache_hit = true
metadata.cache_layer = "L0"
metadata.cache_decision = "reuse"
metadata.path = "fast"
```

L0 is strict by construction because its key includes normalized query, intent,
CEFR level, profile epoch, and session turn.

## 9. L1 Graph-Aware Near-Hit Reuse

L1 exists because many safe requests are not exact string matches:

- "Who founded AlphaSoft?"
- "Who created AlphaSoft?"

These may be equivalent enough to avoid full generation if state is compatible.
The service builds a graph bucket using stable state features:

```python
bucket = build_graph_bucket(fingerprint)
```

Then it evaluates candidates with SCAR-L1.

## 10. SCAR-L1 Decision Logic

`core/scar_l1.py` compares:

- `L1Request`: current request state;
- `L1Candidate`: cached artifact state.

Hard gates reject unsafe candidates before risk scoring:

| Gate | Why it matters |
| --- | --- |
| `level_mismatch` | A C1 answer may be wrong pedagogically for A2. |
| `profile_epoch_mismatch` | Learner progress/profile changed enough to invalidate artifact assumptions. |
| `intent_mismatch` | Explaining, correcting, and asking are different tasks. |
| `answer_target_mismatch` | Person/place/time/number answers are not interchangeable. |
| `evidence_mismatch` | Underlying evidence changed. |
| `relation_mismatch` | Graph relation path changed. |
| `concept_overlap_below_floor` | Near-hit is too semantically far. |
| `stale_candidate` | TTL expired. |

If hard gates pass, risk is computed:

```text
risk =
  0.30 * intent_drift
+ 0.25 * (1 - concept_overlap)
+ 0.20 * (1 - entity_overlap)
+ 0.15 * (1 - relation_overlap)
+ 0.10 * age_ratio
```

Then:

```text
if exact normalized query and risk <= tau_reuse:
    decision = reuse
elif risk <= tau_patch:
    decision = patch
else:
    decision = full
```

Defaults:

```text
tau_reuse = 0.25
tau_patch = 0.55
concept_floor = 0.50
```

This keeps L1 conservative: it accepts only state-compatible near-hits and falls
back to full reconstruction when uncertainty is too high.

## 11. PCC And SCAR-L1 Relationship

PCC means "profile/context/certificate" style safety checking around reuse. In
the current app, PCC logic also lives in `api/services/trace_cag/cache_utils.py`
and includes Redis-backed L0/L1 orchestration, bucket versions, cache writes,
and benchmark-aware policy hooks.

The portable package extracts the safest core idea:

1. represent current state as a fingerprint;
2. represent candidate state as a certificate;
3. apply hard compatibility gates;
4. calculate reuse risk;
5. return `reuse`, `patch`, or `full`.

This lets another project adopt the same reuse safety model without importing
the LexiLingo app.

## 12. Production Adapter Vs Memory Adapter

| Adapter | Use case | Dependencies |
| --- | --- | --- |
| `LexiLingoTraceCAGAnalyzer` | Use current production TRACE-CAG from this repo. | Existing `api.services.trace_cag` stack. |
| `InMemoryTraceCAGAnalyzer` | Tests, demos, new-project scaffold, local examples. | No external services. |
| Custom analyzer | Any other project. | Whatever the project chooses. |

The memory adapter is not a full tutor. It intentionally does not call an LLM.
Its job is to prove and demonstrate the portable cache-state mechanism.

## 13. Implementing A Real Adapter

A real adapter should usually perform these steps:

1. Build request fingerprint.
2. Try L0 exact cache.
3. Try L1 candidate pool plus SCAR-L1.
4. If `reuse`, return cached artifact.
5. If `patch`, adapt the cached artifact and return it with metadata.
6. If `full`, run retrieval, diagnosis, generation, then write a new cache entry.
7. Normalize the result into `TraceCAGResponse`.

Skeleton:

```python
from service.tracecag_service import TraceCAGRequest, TraceCAGResponse
from service.tracecag_service.core import build_cache_key, build_fingerprint, build_graph_bucket


class RealAnalyzer:
    async def analyze(self, request: TraceCAGRequest) -> TraceCAGResponse:
        fingerprint = build_fingerprint(
            user_input=request.user_input,
            learner_profile=request.learner_profile,
            conversation_history=request.conversation_history,
        )
        cache_key = build_cache_key(fingerprint)
        bucket = build_graph_bucket(fingerprint)

        # 1. check exact cache by cache_key
        # 2. check L1 candidates by bucket and decide_l1_reuse
        # 3. run full KG/retrieval/LLM if needed
        # 4. write cache entry
        # 5. return TraceCAGResponse
```

## 14. Voice/STT Boundary

The service contract supports voice through:

```python
TraceCAGRequest(
    user_input=final_transcript_text,
    input_type="voice",
    stt_final=final_event_dict,
)
```

Only final transcripts should enter TRACE-CAG. Partial STT events are UI state
and should not be cached or analyzed as final learner intent.

## 15. Benchmark Hooks

The request preserves current benchmark controls:

- `benchmark_task`
- `benchmark_context`
- `benchmark_metadata`
- `kg_seed_concepts`
- `return_raw_state`

These fields allow benchmark runners to evaluate the production pipeline through
the portable contract without duplicating benchmark-only pipeline code.

## 16. Operational Guarantees

The service wrapper provides:

- strict input validation by default;
- timeout containment;
- non-throwing response errors for boundary failures;
- bounded batch concurrency through `analyze_many`;
- response metadata stamping with service name, version, adapter, session, and
  input type.

Example error handling:

```python
response = await service.analyze_text("")
if response.error:
    print(response.metadata["error_type"], response.error)
```

## 17. Migration Checklist For Another Project

1. Copy `service/tracecag_service` into the target repo.
2. Keep imports stable: `from service.tracecag_service import ...`.
3. Start with `InMemoryTraceCAGAnalyzer` to verify the package imports and tests.
4. Implement a project adapter using `TraceCAGAnalyzer`.
5. Wire cache storage: in-memory, Redis, SQLite, Postgres, or project-specific.
6. Wire KG/retrieval.
7. Wire LLM generation.
8. Preserve metadata keys: `cache_hit`, `cache_decision`, `cache_layer`, `path`,
   `reuse_risk`, and `tokens_saved`.
9. Add tests for L0 reuse, L1 patch, L1 rejection, timeout, and invalid input.

## 18. Verification

Run package tests:

```bash
pytest tests/service -q
```

Expected result:

```text
10 passed
```

These tests intentionally avoid FastAPI startup, Redis, Kuzu, Groq, Gemini, and
network calls.

