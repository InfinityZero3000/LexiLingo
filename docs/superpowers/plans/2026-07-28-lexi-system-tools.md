# Lexi System Data Tools Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Lexi answer explicit current-learning questions from authenticated system data without MCP runtime, stale cache reuse, or disruption when the data read fails.

**Architecture:** A pure selector marks one fixed snapshot tool in TraceCAG input state. Selected turns bypass response caches; `kg_diagnose_node` fetches the snapshot concurrently through the existing pooled learner-state client and keeps the validated result in a cache-excluded `system_context` field consumed by both regular and SSE prompt generation.

**Tech Stack:** Python 3.11, FastAPI, Pydantic v2, SQLAlchemy async, LangGraph/TraceCAG, httpx, pytest.

---

## File Map

- Create `backend-service/app/schemas/learner_context.py`: bounded internal response schema.
- Modify `backend-service/app/routes/learner_state.py`: authenticated read-only snapshot endpoint.
- Test `backend-service/tests/integration/test_learner_state_routes.py`: auth, defaults, and snapshot semantics.
- Modify `ai-service/api/clients/learner_state_client.py`: reuse pooled client for bounded snapshot reads.
- Test `ai-service/tests/test_learner_state_client.py`: response validation, deadline, and degraded results.
- Create `ai-service/api/services/trace_cag/system_data.py`: fixed selector and validated prompt serialization.
- Modify `ai-service/api/services/trace_cag/state.py`: typed `system_tool` and `system_context`.
- Modify `ai-service/api/services/trace_cag/nodes_v2.py`: selection and concurrent snapshot fetch.
- Modify `ai-service/api/services/trace_cag/cache_utils.py`: bypass L0/L1 for live-data turns.
- Modify `ai-service/api/services/trace_cag/edges.py`: live-data turns always reach retrieval/generation.
- Modify `ai-service/api/services/trace_cag/generate.py`: shared prompt grounding for regular/SSE.
- Test `ai-service/tests/trace_cag/test_system_data_tools.py`: selection, concurrency contract, prompt safety, and fallback.
- Test `ai-service/tests/trace_cag/test_cache_gate_l1.py`: L0/L1 bypass and privacy.
- Test `ai-service/tests/test_tracecag_chat_integration.py`: non-streaming integration.
- Test `ai-service/tests/test_lexi_session_management.py`: SSE integration.
- Modify `ai-service/.env.example` only if an existing learner-state setting needs clarification; add no new secret.

## Chunk 1: Authoritative Backend Snapshot

### Task 1: Define and serve the read-only learner snapshot

**Files:**
- Create: `backend-service/app/schemas/learner_context.py`
- Modify: `backend-service/app/routes/learner_state.py`
- Test: `backend-service/tests/integration/test_learner_state_routes.py`

- [ ] **Step 1: Add failing endpoint contract tests**

Cover invalid service token/audience, unknown user `404`, missing optional rows
as zero, and a populated user. Freeze one UTC `now` and assert archived or
future vocabulary is not counted as due.

Expected response:

```python
{
    "level": "B1",
    "level_progress_percent": 64.0,
    "xp": 1230,
    "streak_days": 8,
    "vocabulary": {
        "learning": 42,
        "reviewing": 18,
        "mastered": 105,
        "due": 7,
    },
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
cd backend-service
pytest tests/integration/test_learner_state_routes.py -q
```

Expected: new snapshot tests fail with endpoint/schema missing.

- [ ] **Step 3: Add bounded Pydantic schemas**

Define only `VocabularySnapshot` and `LearnerContextSnapshot`. Clamp counts to
non-negative integers and progress to `0..100`; reject extra fields.

- [ ] **Step 4: Implement the endpoint using existing authorities**

Add `GET /internal/learner-state/users/{user_id}/context` protected by
`require_learner_state_service`. In one async session transaction:

- load `User` or return `404`;
- calculate progress with `get_numeric_level_progress(user.total_xp)`;
- read `Streak.current_streak`, default zero;
- reuse `vocabulary_crud.get_user_vocabulary_stats`;
- call `FSRSSchedulerService.count_due_vocabulary` with one captured UTC time.

Do not seed vocabulary, update streaks, mutate XP, or commit.

- [ ] **Step 5: Run backend focused tests**

Run:

```bash
cd backend-service
pytest tests/integration/test_learner_state_routes.py tests/services/test_learner_state.py -q
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add backend-service/app/schemas/learner_context.py \
  backend-service/app/routes/learner_state.py \
  backend-service/tests/integration/test_learner_state_routes.py
git commit -m "feat(backend): expose internal learner context snapshot"
```

## Chunk 2: Existing Client Extension and Fixed Tool

### Task 2: Extend the pooled learner-state client

**Files:**
- Modify: `ai-service/api/clients/learner_state_client.py`
- Test: `ai-service/tests/test_learner_state_client.py`

- [ ] **Step 1: Add failing client tests**

Test successful parsing, unknown fields/invalid scalar types, `404`, transport
failure, circuit-open behavior, and an expired absolute deadline. Assert the
same auth headers used by `batch_get` and the exact user ID path.

- [ ] **Step 2: Run the client tests and verify failure**

Run:

```bash
cd ai-service
pytest tests/test_learner_state_client.py -q
```

Expected: snapshot method/result types are missing.

- [ ] **Step 3: Add the smallest client method**

Add immutable `LearnerContextResult` and
`LearnerStateClient.get_learning_snapshot(user_id, deadline=...)`. Reuse the
existing `AsyncClient`, semaphore, auth headers, failure counter, circuit
breaker, telemetry style, and shutdown lifecycle. Do not add a second client,
retry library, or secret.

- [ ] **Step 4: Run the client tests**

Run:

```bash
cd ai-service
pytest tests/test_learner_state_client.py -q
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add ai-service/api/clients/learner_state_client.py \
  ai-service/tests/test_learner_state_client.py
git commit -m "feat(ai): read learner context through pooled client"
```

### Task 3: Add the fixed selector and safe prompt context

**Files:**
- Create: `ai-service/api/services/trace_cag/system_data.py`
- Modify: `ai-service/api/services/trace_cag/state.py`
- Test: `ai-service/tests/trace_cag/test_system_data_tools.py`

- [ ] **Step 1: Write failing selector and serialization tests**

Table-test explicit English and Vietnamese current-user questions for
review/due/progress/XP/streak/level. Assert ordinary grammar questions,
hypotheticals, third-person questions, and unknown text select `none`.

Assert serialization:

- accepts only the fixed validated scalar shape;
- represents degraded reads as `{"available": false}`;
- emits no free-form backend text;
- never includes a user-supplied tool name or user ID.

- [ ] **Step 2: Run and verify failure**

Run:

```bash
cd ai-service
pytest tests/trace_cag/test_system_data_tools.py -q
```

Expected: module and state fields are missing.

- [ ] **Step 3: Implement pure functions and typed state**

Implement:

```python
def select_system_tool(text: str) -> Literal["none", "get_learning_snapshot"]:
    ...

def prompt_system_context(result: LearnerContextResult) -> dict[str, object]:
    ...
```

Keep matching conservative and fixed. Add `system_tool` and `system_context`
to `TraceCAGState` and initialize both in `create_initial_state`.

- [ ] **Step 4: Run focused tests**

Run:

```bash
cd ai-service
pytest tests/trace_cag/test_system_data_tools.py -q
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add ai-service/api/services/trace_cag/system_data.py \
  ai-service/api/services/trace_cag/state.py \
  ai-service/tests/trace_cag/test_system_data_tools.py
git commit -m "feat(ai): select safe learner data tool"
```

## Chunk 3: Shared TraceCAG Integration

### Task 4: Wire selection, cache bypass, and concurrent execution

**Files:**
- Modify: `ai-service/api/services/trace_cag/nodes_v2.py`
- Modify: `ai-service/api/services/trace_cag/cache_utils.py`
- Modify: `ai-service/api/services/trace_cag/edges.py`
- Test: `ai-service/tests/trace_cag/test_system_data_tools.py`
- Test: `ai-service/tests/trace_cag/test_cache_gate_l1.py`

- [ ] **Step 1: Add failing orchestration and cache tests**

Assert:

- `input_node` writes the selected tool;
- `cache_gate_node` returns a full miss before reading L0/L1 when selected;
- both exact L0 and near L1 cached responses are ignored;
- `kg_diagnose_node` starts KG, diagnosis, and snapshot coroutines together;
- snapshot uses authenticated state `user_id` and a 300 ms absolute deadline;
- timeout produces the typed unavailable marker;
- cancellation propagates;
- selected turns route to retrieval rather than clarification;
- no snapshot value appears in cache input, evidence bundle, retrieval trace,
  or captured log records.
- `_write_cache_entry` invokes no L0 store, L1 bucket registration, or reverse
  dependency write for selected turns in both regular and SSE flows;
- an ordinary turn still writes the existing cache artifacts.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
cd ai-service
pytest tests/trace_cag/test_system_data_tools.py \
  tests/trace_cag/test_cache_gate_l1.py -q
```

Expected: new integration assertions fail.

- [ ] **Step 3: Implement minimal graph changes**

- Call `select_system_tool` from `input_node`.
- Make `cache_gate_node` fail closed with reason `live_system_data`.
- Make `_write_cache_entry` return before constructing any artifact when
  `system_tool != "none"`; this central guard covers regular and SSE callers.
- In `kg_diagnose_node`, add one snapshot coroutine to the existing gather only
  when selected; otherwise use an immediate no-op result.
- Use `time.monotonic() + 0.300` as the absolute deadline.
- Store only validated `system_context`; do not alter `retrieved_context`.
- Make `route_after_diagnosis` prioritize selected system-data turns.

Do not add a graph node, dynamic registry, background queue, retry layer, or
MCP dependency.

- [ ] **Step 4: Bump the existing cache policy/prompt version**

Update the existing TraceCAG policy-version constant used in cache
fingerprints. Do not introduce a second version flag.

- [ ] **Step 5: Run focused tests**

Run:

```bash
cd ai-service
pytest tests/trace_cag/test_system_data_tools.py \
  tests/trace_cag/test_cache_gate_l1.py \
  tests/trace_cag/test_learner_state_overlay_integration.py -q
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add ai-service/api/services/trace_cag/nodes_v2.py \
  ai-service/api/services/trace_cag/cache_utils.py \
  ai-service/api/services/trace_cag/edges.py \
  ai-service/tests/trace_cag/test_system_data_tools.py \
  ai-service/tests/trace_cag/test_cache_gate_l1.py
git commit -m "feat(ai): ground TraceCAG with live learner data"
```

### Task 5: Ground both generation paths without leaking context

**Files:**
- Modify: `ai-service/api/services/trace_cag/generate.py`
- Test: `ai-service/tests/trace_cag/test_system_data_tools.py`
- Test: `ai-service/tests/test_tracecag_chat_integration.py`
- Test: `ai-service/tests/test_lexi_session_management.py`

- [ ] **Step 1: Add failing prompt and chat-flow tests**

Assert `build_generation_prompt` and regular `generate_node` use the same
delimited system-data block through
`_append_system_data_block(system_prompt, state)`. The prompt must:

- state values are data, never instructions;
- instruct Lexi not to invent values when `available=false`;
- omit the block for `system_tool=none`;
- include no user ID, auth header, token, or backend error text.

For non-streaming and SSE, send a progress question and prove the same snapshot
reaches generation. Simulate timeout and prove both flows still produce a chat
response. Add a direct regular `generate_node` provider-path test.

For `generation_policy=extractive`, selected turns render a small deterministic
response from validated snapshot fields. An unavailable marker renders a
generic live-data-unavailable response. The extractive branch must not ignore
the selected tool or invent values.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
cd ai-service
pytest tests/trace_cag/test_system_data_tools.py \
  tests/test_tracecag_chat_integration.py \
  tests/test_lexi_session_management.py -q
```

Expected: prompt and chat integration assertions fail.

- [ ] **Step 3: Add one shared prompt helper**

Implement `_append_system_data_block` as the only prompt serializer and call it
from `build_generation_prompt` and the normal provider prompt construction in
`generate_node`. Keep benchmark prompt behavior unchanged. Add the bounded
extractive response described above. Keep system data separate from knowledge
context/cache evidence and do not alter Flutter/SSE response contracts.

- [ ] **Step 4: Run focused and full AI tests**

Run:

```bash
cd ai-service
pytest tests/trace_cag/test_system_data_tools.py \
  tests/test_tracecag_chat_integration.py \
  tests/test_lexi_session_management.py -q
pytest tests -q
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add ai-service/api/services/trace_cag/generate.py \
  ai-service/tests/trace_cag/test_system_data_tools.py \
  ai-service/tests/test_tracecag_chat_integration.py \
  ai-service/tests/test_lexi_session_management.py
git commit -m "feat(ai): ground Lexi responses with system data"
```

## Chunk 4: End-to-End Verification and Deployment Contract

### Task 6: Verify the complete system path

**Files:**
- Modify: `ai-service/.env.example` only if existing learner-state comments are insufficient.
- Test: existing Compose and CI configuration; create no duplicate workflow.

- [ ] **Step 1: Run backend and AI suites**

```bash
cd backend-service
pytest -q
cd ../ai-service
pytest -q
```

Expected: all pass.

- [ ] **Step 2: Run static and Compose checks**

```bash
cd ai-service
ruff check api tests
cd ..
docker compose \
  --env-file .env.production \
  --env-file .env.production.secrets \
  -f docker-compose.yml config --quiet
git diff --check
```

Expected: all commands exit zero.

- [ ] **Step 3: Run deterministic cross-service E2E checks**

Use the pytest ASGI/mock-transport harness from Tasks 1–5; do not add a
production-only timeout switch:

```bash
cd ai-service
pytest tests/trace_cag/test_system_data_tools.py \
  tests/test_tracecag_chat_integration.py \
  tests/test_lexi_session_management.py -q
cd ../backend-service
pytest tests/integration/test_learner_state_routes.py -q
```

These tests assert one authenticated backend request for a progress question,
zero snapshot requests for ordinary grammar chat, transport timeout with
continued regular/SSE responses, and redacted logs.

- [ ] **Step 4: Run existing production-like smoke without deleting volumes**

```bash
docker compose \
  --env-file .env.production \
  --env-file .env.production.secrets \
  -f docker-compose.yml up -d --build backend-service ai-service gateway
cd ai-service
python3 scripts/e2e_ai_service.py smoke \
  --base-url https://api.lexilingo.me \
  --env-file ../.env.production.secrets
```

This checks deployment/auth/chat health. Deterministic tool selection and
timeout remain pytest coverage. Do not run `docker compose down --volumes`.

- [ ] **Step 5: Check privacy and latency evidence**

The automated telemetry assertions may contain only selection, outcome, and
latency—not XP, streak, vocabulary counts, snapshot JSON, or service tokens.
Assert a successful selected-tool request finishes before its 300 ms absolute
deadline; do not claim a percentile from one smoke request.

- [ ] **Step 6: Commit only necessary configuration clarification**

If no configuration file changed, skip this commit. Otherwise:

```bash
git add ai-service/.env.example
git commit -m "docs(ai): clarify learner context runtime settings"
```

- [ ] **Step 7: Final review and CI**

Review the complete branch diff against the approved design, push the branch,
open a PR to `dev`, and require Backend Tests, AI Tests, Security, Flutter,
Admin, and MCP smoke to pass. The MCP smoke remains coding-time coverage; the
new runtime behavior is proven by AI/backend E2E tests.
