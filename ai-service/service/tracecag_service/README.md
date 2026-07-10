# TRACE-CAG Service Package

`service/tracecag_service` is the portable packaging layer for TRACE-CAG. It
lets another Python project call the TRACE-CAG contract without importing the
FastAPI app at module import time.

The existing LexiLingo app remains unchanged. The production adapter imports
`api.services.trace_cag.graph.get_trace_cag()` lazily only when the first
analysis request runs.

## What This Package Contains

| File | Purpose |
| --- | --- |
| `schemas.py` | Stable `TraceCAGRequest` and `TraceCAGResponse` DTOs. |
| `runtime.py` | `TraceCAGService`: validation, timeout, batch concurrency, response normalization. |
| `ports.py` | `TraceCAGAnalyzer` protocol for pluggable implementations. |
| `config.py` | Portable config and env loading via `TRACECAG_SERVICE_*`. |
| `core/fingerprint.py` | Lightweight state fingerprinting for cache keys and L1 buckets. |
| `core/scar_l1.py` | Pure SCAR-L1 reuse/patch/full decision logic. |
| `adapters/lexilingo.py` | Lazy bridge to the current LexiLingo TRACE-CAG pipeline. |
| `adapters/memory.py` | Dependency-free adapter for tests, demos, and new projects. |

## Quick Start Inside LexiLingo

```python
from service.tracecag_service import TraceCAGRequest
from service.tracecag_service.adapters.lexilingo import create_lexilingo_service

service = create_lexilingo_service()

response = await service.analyze(
    TraceCAGRequest(
        user_input="I go to school yesterday.",
        session_id="session-1",
        user_id="user-1",
        learner_profile={"level": "B1"},
    )
)

print(response.tutor_response)
print(response.metadata["cache_decision"])
```

Use this when you want the portable contract but still want the existing
LexiLingo KG, Redis, model gateway, and LangGraph runtime.

## Quick Start In Another Project

Copy or vendor the `service/tracecag_service` package, then implement the
`TraceCAGAnalyzer` port:

```python
from service.tracecag_service import TraceCAGRequest, TraceCAGResponse, TraceCAGService


class MyAnalyzer:
    async def analyze(self, request: TraceCAGRequest) -> TraceCAGResponse:
        # Connect your KG, cache, retriever, LLM, or workflow here.
        return TraceCAGResponse(
            tutor_response=f"Handled: {request.user_input}",
            metadata={"path": "slow", "cache_hit": False},
        )


service = TraceCAGService(MyAnalyzer())
response = await service.analyze_text("Explain past simple", session_id="demo")
```

The service wrapper does not care whether the implementation is LangGraph,
FastAPI, a CLI tool, a notebook, or a background worker. The only required
method is:

```python
async def analyze(request: TraceCAGRequest) -> TraceCAGResponse | dict:
    ...
```

## Dependency-Free Demo Adapter

The memory adapter proves the package works without Redis, Kuzu, FastAPI, or
LLM keys. It implements lightweight L0 exact reuse and L1 SCAR-style near-hit
reuse.

```python
from service.tracecag_service import TraceCAGService
from service.tracecag_service.adapters.memory import InMemoryTraceCAGAnalyzer

service = TraceCAGService(InMemoryTraceCAGAnalyzer())

first = await service.analyze_text("Who founded AlphaSoft?", session_id="s1")
second = await service.analyze_text("Who founded AlphaSoft?", session_id="s1")
near = await service.analyze_text("Who created AlphaSoft?", session_id="s1")

assert first.metadata["cache_decision"] == "full"
assert second.metadata["cache_layer"] == "L0"
assert near.metadata["cache_layer"] == "L1"
```

Use it for package-level tests or as a placeholder while wiring a real project
adapter.

## Request Fields

`TraceCAGRequest` is intentionally close to the current pipeline signature:

| Field | Meaning |
| --- | --- |
| `user_input` | Required user text or final transcript. |
| `session_id` | Conversation/session boundary for history and cache state. |
| `user_id` | Optional user identity for personalization. |
| `input_type` | `"text"` or `"voice"`. |
| `learner_profile` | Level, errors, progress, vocabulary count, or project-specific profile fields. |
| `conversation_history` | Already-loaded turns. Supplying it lets callers skip a store lookup. |
| `stt_final` | Optional final-only STT event payload. |
| `cache_policy` | `"on"` or `"off"`. |
| `retrieval_policy` | Existing pipeline retrieval knob, usually `"full"` or `"rapid"`. |
| `diagnosis_policy` | Existing pipeline diagnosis knob, usually `"auto"` or `"rules"`. |
| `generation_policy` | Existing generation knob, including `"auto"` or `"skip"` for streaming prep. |
| `benchmark_*` | Optional benchmark task/context/metadata hooks. |
| `kg_seed_concepts` | Preloaded graph concepts from another cache or caller. |
| `return_raw_state` | Ask adapters to attach raw pipeline state when supported. |

## Response Fields

`TraceCAGResponse` normalizes either a dataclass response or a raw dict:

| Field | Meaning |
| --- | --- |
| `tutor_response` | Final user-facing text. |
| `corrections` | Grammar or language feedback objects. |
| `linked_concepts` | KG or lightweight concept IDs used by the response. |
| `action_plan` | Suggested follow-up actions. |
| `scores` | Fluency, grammar, overall, vocabulary, or project-specific metrics. |
| `action` | Strategy and next action. |
| `metadata` | Latency, cache path, cache decision, service adapter, and request metadata. |
| `raw_state` | Optional raw implementation state. |
| `error` | Non-throwing error string for validation, timeout, or runtime failure. |

## Runtime Configuration

```python
from service.tracecag_service import TraceCAGServiceConfig

config = TraceCAGServiceConfig(
    timeout_seconds=20,
    max_concurrency=2,
    include_raw_state_by_default=False,
)
```

Environment variables use the `TRACECAG_SERVICE_` prefix:

| Env var | Default |
| --- | --- |
| `TRACECAG_SERVICE_NAME` | `tracecag-service` |
| `TRACECAG_SERVICE_VERSION` | `0.1.0` |
| `TRACECAG_SERVICE_TIMEOUT_SECONDS` | `30.0` |
| `TRACECAG_SERVICE_MAX_CONCURRENCY` | `4` |
| `TRACECAG_SERVICE_DEFAULT_SESSION_ID` | `tracecag-session` |
| `TRACECAG_SERVICE_INCLUDE_RAW_STATE` | `false` |
| `TRACECAG_SERVICE_STRICT_VALIDATION` | `true` |

## Batch Calls

```python
requests = [
    TraceCAGRequest(user_input="Explain articles", session_id="s1"),
    TraceCAGRequest(user_input="Practice past tense", session_id="s2"),
]

responses = await service.analyze_many(requests)
```

`TraceCAGService` bounds parallelism with `max_concurrency`.

## Error Handling

The wrapper returns errors as `TraceCAGResponse` instead of raising for common
service boundary failures:

- validation: empty input, missing session, unsupported input type, invalid cache policy
- timeout: analyzer exceeded `timeout_seconds`
- runtime: analyzer raised an exception

Check:

```python
if response.error:
    print(response.metadata["error_type"], response.error)
```

## Theory And Mechanism

For the full explanation of the cache theory, PCC/SCAR-L1 decision flow, and
how to implement this package in another project, read:

`docs/tracecag_service_guide.md`

## Tests

```bash
pytest tests/service -q
```

These tests do not start FastAPI, Redis, KG, or any model provider.
