# Lexi System Data Tools Design

## Goal

Let Lexi automatically use current learner data when a chat question needs it,
without adding MCP runtime infrastructure or slowing ordinary conversation.

## Decision

Use one fixed, in-process read tool in `ai-service`. A conservative pure
selector marks explicit current-learner-data questions before the response
cache. It adds no model or network round-trip to ordinary chat.

`mcp-server/` remains coding-time infrastructure and is not placed on the
production chat path.

## Initial Scope

Expose one read-only tool:

- `get_learning_snapshot`: current level/progress, XP/streak, vocabulary
  totals, and due-review count for the authenticated learner.

One snapshot avoids multiple backend round-trips and overlapping tools. It is
enough for questions such as:

- "What should I review today?"
- "How many words are due?"
- "How is my progress?"
- "What is my streak/XP/level?"

Lesson mutation, review submission, purchases, account changes, arbitrary SQL,
and admin data are out of scope.

## Data Flow

```text
Flutter Lexi chat
  -> existing /api/v1/lexi/chat or /stream
  -> TraceCAG input_node
       -> select "none" | "get_learning_snapshot" from explicit
          current-user progress/review/streak/XP intent
  -> cache_gate_node
       -> no tool: existing cache behavior
       -> selected tool: force cache miss
  -> kg_diagnose_node
       -> existing KG expansion, diagnosis, and selected snapshot read run
          concurrently
  -> retrieve_node
       -> keep retrieval evidence and system_context separate
  -> existing generate_node / SSE generation
```

The frontend contract does not change. Streaming and non-streaming both consume
the same enriched TraceCAG state.

## Selection Rules

The selector recognizes only explicit questions about the authenticated
learner's current review queue, progress, XP, streak, or level. Its allowlist
is a fixed mapping, not a registry framework. False positives cost one bounded
read; unknown or ambiguous conversation selects `none`.

Parsing is fail-closed:

- missing or unknown selection becomes `none`;
- callers cannot provide a tool name or arguments;
- the tool injects the authenticated `user_id`;
- at most one read-only tool runs per turn.

No agent loop, model call, package, dynamic registration, or user-supplied tool
argument is introduced.

### Exact TraceCAG topology

`input_node` writes `system_tool`. `cache_gate_node` immediately returns a miss
for any non-`none` value, so L0/L1 cannot serve stale personalized answers.
`kg_diagnose_node` adds the snapshot coroutine to its existing `gather`.
`route_after_diagnosis` sends a selected system-data turn to `retrieve_node`
even if generic diagnosis would ask for clarification. `retrieve_node` leaves
`system_context` untouched. `generate_node` reads it when generation is
enabled; `generation_policy=skip` still returns the enriched raw state used by
SSE prompt construction.

Snapshot-dependent responses are never written to L0/L1. Cache rollout bumps
the prompt/policy version so old answers to these intents cannot survive the
deployment. Regression tests cover prior L0 and L1 hits with changed snapshot
data in both non-streaming and SSE paths.

## Backend Contract

Add one service-authenticated, read-only internal endpoint beside the existing
learner-state routes. It executes one consistent read transaction and returns
a bounded Pydantic response from these authoritative sources:

- CEFR: `User.level`;
- numeric progress and XP: `User.total_xp` plus
  `get_numeric_level_progress`;
- streak: `Streak.current_streak`, defaulting to zero when absent;
- vocabulary status totals:
  `vocabulary_crud.get_user_vocabulary_stats`;
- due count: `FSRSSchedulerService.count_due_vocabulary` at one captured UTC
  timestamp, excluding archived rows.

```json
{
  "level": "B1",
  "level_progress_percent": 64.0,
  "xp": 1230,
  "streak_days": 8,
  "vocabulary": {
    "learning": 42,
    "reviewing": 18,
    "mastered": 105,
    "due": 7
  }
}
```

`level_progress_percent` is clamped to `0..100` using the existing level
service calculation. Missing user returns 404. Missing optional stats rows
return zero. The read path never calls seeding, streak update, review, XP, or
other mutating helpers.

The endpoint uses the existing learner-state service token and audience
headers. It never accepts another user identity from the chat client; AI
service supplies the authenticated request user.

## Runtime and Latency

- `system_tool=none`: one pure selector call; no I/O.
- selected tool: one internal request, concurrent with existing KG/diagnosis.
- extend the process-wide `LearnerStateClient`; reuse its pool, auth headers,
  bulkhead, circuit breaker, telemetry, and shutdown lifecycle.
- snapshot deadline is 300 ms total. Timeout cancels the request; chat request
  cancellation still propagates.
- snapshot size is capped before prompt insertion.
- tool context is marked as system data and treated as untrusted text, not as
  instructions.

No MCP container, discovery request, retry queue, new database, or new package
is added.

## Failure Handling

Tool timeout, backend 4xx/5xx, invalid response, or open circuit produces a
typed unavailable marker and continues the existing TraceCAG response.

Failures are logged without learner contents and emit counters for selected,
success, degraded, and latency. Cancellation still propagates. The user does
not receive an internal error or fabricated personal values.

The generation prompt is told to acknowledge unavailable live data when the
question explicitly requires it, rather than inventing values.

`system_context` is a separate typed state field. It is never concatenated into
`retrieved_context`, cache evidence, retrieval traces, logs, telemetry tags, or
persisted cache artifacts. Prompt construction serializes only the validated
scalar response inside a clearly delimited system-data block.

## Testing

Small runnable checks cover:

1. selector selects snapshot for explicit current-progress/review questions;
2. ordinary tutoring selects no tool;
3. unknown tool values are rejected;
4. tool injects authenticated user identity and validates the response;
5. timeout returns the typed unavailable marker and generation continues;
6. non-streaming chat includes snapshot context;
7. SSE chat includes the same context;
8. backend endpoint rejects missing/invalid service identity;
9. an end-to-end service test sends a progress question and proves the backend
   snapshot reaches the generated prompt.
10. selected turns bypass existing L0/L1 answers and are not cached;
11. cache records, logs, and retrieval evidence contain no snapshot values.

Existing AI, backend, Flutter, security, and Compose checks remain required.

## Upgrade Path

Add another fixed tool only when a real user question cannot be answered by the
snapshot.
