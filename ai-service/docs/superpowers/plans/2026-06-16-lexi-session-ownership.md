# Lexi Session Ownership Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent authenticated users from reading, continuing, overwriting, or hijacking another user's Lexi chat session when they submit a `session_id` to `/api/v1/lexi/chat` or `/api/v1/lexi/stream`.

**Architecture:** Treat an omitted `session_id` as "create a new Lexi session" and a supplied `session_id` as "continue an existing session that must belong to the current user." Add one shared ownership/session-preparation path in `lexi_chat.py` and call it before idempotency cache lookup, pipeline execution, and streaming response creation.

**Tech Stack:** FastAPI, Motor/MongoDB, Redis-backed `LexiSessionStore`, pytest-asyncio, existing `AuthenticatedUser` and `enforce_user_scope`.

---

## File Structure

- Modify: `ai-service/api/routes/lexi_chat.py`
  - Add shared helpers for existing-session verification and new-session creation.
  - Use the helpers in `lexi_chat()` and `lexi_stream_chat()`.
  - Keep existing `_ensure_session_owner()` behavior for migrated rows with empty `user_id`.
- Modify: `ai-service/tests/test_lexi_chat_routes.py`
  - Add route-level tests for `/chat` ownership enforcement.
  - Add route-level tests for `/stream` preflight ownership enforcement.
- Optional modify: `ai-service/tests/test_lexi_session_management.py`
  - Only if duplicated helper tests fit better beside existing session-management tests.

## Decisions

- New session: only when request omits `session_id`.
- Existing session: when request provides `session_id`, require Mongo or Redis cache to contain that session and verify owner.
- Missing supplied session: return `404 Session not found`; do not silently create or upsert that client-provided ID.
- Owner mismatch: return `403 Forbidden: session ownership mismatch`.
- Legacy/migrated session with empty `user_id`: allow current user to continue; next write may set `user_id` as existing code already does.
- Streaming endpoint: ownership failures should raise HTTP 403/404 before `StreamingResponse` is returned, not as an SSE `error` event after a 200 response.

---

### Task 1: Add Failing Tests For `/chat` Ownership

**Files:**
- Modify: `ai-service/tests/test_lexi_chat_routes.py`

- [ ] **Step 1: Add test for Mongo-owned session mismatch**

Add a test near the existing `lexi_chat` tests:

```python
@pytest.mark.asyncio
async def test_lexi_chat_rejects_session_owned_by_another_user(
    mock_store,
    mock_idempotency,
    monkeypatch,
):
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))

    mock_store.has_session = AsyncMock(return_value=False)
    mock_store.get_messages = AsyncMock(return_value=[])
    db = _make_db(session_doc={"session_id": "sess-other", "user_id": "owner-1"})

    run_pipeline = AsyncMock()
    monkeypatch.setattr(lexi_route, "_run_lexi_pipeline", run_pipeline)

    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="attacker-1",
                session_id="sess-other",
                message="continue",
            ),
            x_idempotency_key=None,
            db=db,
            current_user=_user("attacker-1"),
        )

    assert exc_info.value.status_code == 403
    run_pipeline.assert_not_called()
    mock_idempotency.get.assert_not_called()
```

- [ ] **Step 2: Add test for missing supplied session**

```python
@pytest.mark.asyncio
async def test_lexi_chat_rejects_unknown_supplied_session_id(
    mock_store,
    mock_idempotency,
    monkeypatch,
):
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))

    mock_store.has_session = AsyncMock(return_value=False)
    mock_store.get_session = AsyncMock(return_value=None)
    mock_store.get_messages = AsyncMock(return_value=[])
    db = _make_db(session_doc=None)

    run_pipeline = AsyncMock()
    monkeypatch.setattr(lexi_route, "_run_lexi_pipeline", run_pipeline)

    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="u1",
                session_id="missing-session",
                message="hello",
            ),
            x_idempotency_key=None,
            db=db,
            current_user=_user("u1"),
        )

    assert exc_info.value.status_code == 404
    run_pipeline.assert_not_called()
    mock_idempotency.get.assert_not_called()
```

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
cd ai-service
pytest tests/test_lexi_chat_routes.py::test_lexi_chat_rejects_session_owned_by_another_user tests/test_lexi_chat_routes.py::test_lexi_chat_rejects_unknown_supplied_session_id -v
```

Expected: both tests fail because current `lexi_chat()` trusts or creates supplied `session_id`.

---

### Task 2: Implement Shared Existing-Session Verification

**Files:**
- Modify: `ai-service/api/routes/lexi_chat.py`

- [ ] **Step 1: Add helper for cached session owner checks**

Place near `_ensure_session_owner()`:

```python
def _assert_cached_session_owner(
    cached_session: Dict[str, Any] | None,
    current_user: AuthenticatedUser,
) -> None:
    if not cached_session:
        return
    owner_user_id = str(cached_session.get("user_id") or "")
    if owner_user_id and owner_user_id != current_user.user_id:
        raise HTTPException(status_code=403, detail="Forbidden: session ownership mismatch")
```

- [ ] **Step 2: Add helper for existing session preparation**

```python
async def _prepare_existing_lexi_session(
    session_id: str,
    current_user: AuthenticatedUser,
    db: AsyncIOMotorDatabase,
) -> List[Dict[str, Any]]:
    try:
        session_doc = await _ensure_session_owner(session_id, current_user, db)
    except HTTPException as exc:
        if exc.status_code != 404:
            raise
        cached_session = await _store.get_session(session_id)
        _assert_cached_session_owner(cached_session, current_user)
        if cached_session:
            return await _store.get_messages(session_id)
        raise

    cached_session = await _store.get_session(session_id)
    _assert_cached_session_owner(cached_session, current_user)
    if cached_session:
        return await _store.get_messages(session_id)

    docs = await (
        db["lexi_messages"]
        .find({"session_id": session_id})
        .sort("timestamp", -1)
        .limit(10)
        .to_list(length=10)
    )
    docs.reverse()
    return [
        {
            "id": doc.get("id") or doc.get("message_id") or str(doc.get("_id", "")),
            "role": doc.get("role", "user"),
            "content": doc.get("content", ""),
            "timestamp": to_iso_timestamp(doc.get("timestamp")),
        }
        for doc in docs
    ]
```

- [ ] **Step 3: Add helper for new session creation**

Extract the current "not exists" block from `lexi_chat()` into:

```python
async def _create_lexi_session_for_user(
    session_id: str,
    user_id: str,
    story_context: Optional[str],
    db: AsyncIOMotorDatabase,
) -> None:
    now_iso = datetime.now(timezone.utc).isoformat()
    await asyncio.gather(
        _store.set_session(session_id, {
            "session_id": session_id,
            "user_id": user_id,
            "created_at": now_iso,
            "updated_at": now_iso,
            "title": "Lexi Chat",
            "message_count": 0,
            "persona": "lexi",
            "story_context": story_context,
        }),
        _store.init_messages(session_id),
        db["lexi_sessions"].update_one(
            {"session_id": session_id},
            {"$set": {
                "session_id": session_id,
                "user_id": user_id,
                "title": "Lexi Chat",
                "created_at": now_iso,
                "updated_at": now_iso,
                "message_count": 0,
                "persona": "lexi",
            }},
            upsert=True,
        ),
    )
```

- [ ] **Step 4: Run syntax check**

Run:

```bash
python3 -m py_compile ai-service/api/routes/lexi_chat.py
```

Expected: no output.

---

### Task 3: Wire `/chat` To The Ownership Helpers

**Files:**
- Modify: `ai-service/api/routes/lexi_chat.py`
- Test: `ai-service/tests/test_lexi_chat_routes.py`

- [ ] **Step 1: Replace current session-management block in `lexi_chat()`**

Use this shape:

```python
if request.session_id:
    session_id = request.session_id
    history = await _prepare_existing_lexi_session(session_id, current_user, db)
else:
    session_id = str(uuid.uuid4())
    history = []
    await _create_lexi_session_for_user(
        session_id=session_id,
        user_id=request.user_id,
        story_context=request.story_context,
        db=db,
    )
```

Important: keep this before `_idempotency_request_hash()` and `_idempotency_store.get()` so cached idempotency responses cannot bypass ownership checks.

- [ ] **Step 2: Run targeted tests**

Run:

```bash
cd ai-service
pytest tests/test_lexi_chat_routes.py -v
```

Expected: pass.

- [ ] **Step 3: Commit**

```bash
git add ai-service/api/routes/lexi_chat.py ai-service/tests/test_lexi_chat_routes.py
git commit -m "fix(ai): enforce Lexi chat session ownership"
```

---

### Task 4: Add `/stream` Ownership Preflight Tests

**Files:**
- Modify: `ai-service/tests/test_lexi_chat_routes.py`

- [ ] **Step 1: Add stream mismatch test**

```python
@pytest.mark.asyncio
async def test_lexi_stream_rejects_session_owned_by_another_user(
    mock_store,
    monkeypatch,
):
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))

    db = _make_db(session_doc={"session_id": "sess-other", "user_id": "owner-1"})
    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_stream_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="attacker-1",
                session_id="sess-other",
                message="hello",
            ),
            db=db,
            current_user=_user("attacker-1"),
        )

    assert exc_info.value.status_code == 403
```

- [ ] **Step 2: Add stream missing-session test**

```python
@pytest.mark.asyncio
async def test_lexi_stream_rejects_unknown_supplied_session_id(
    mock_store,
    monkeypatch,
):
    from fastapi import HTTPException

    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: cu.user_id)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    mock_store.get_session = AsyncMock(return_value=None)

    db = _make_db(session_doc=None)
    request_ctx = MagicMock()
    request_ctx.headers = {}

    with pytest.raises(HTTPException) as exc_info:
        await lexi_route.lexi_stream_chat(
            request_context=request_ctx,
            request=lexi_route.LexiChatRequest(
                user_id="u1",
                session_id="missing-session",
                message="hello",
            ),
            db=db,
            current_user=_user("u1"),
        )

    assert exc_info.value.status_code == 404
```

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
cd ai-service
pytest tests/test_lexi_chat_routes.py::test_lexi_stream_rejects_session_owned_by_another_user tests/test_lexi_chat_routes.py::test_lexi_stream_rejects_unknown_supplied_session_id -v
```

Expected: fail because `lexi_stream_chat()` does not preflight existing-session ownership before returning `StreamingResponse`.

---

### Task 5: Wire `/stream` To The Ownership Helpers

**Files:**
- Modify: `ai-service/api/routes/lexi_chat.py`
- Test: `ai-service/tests/test_lexi_chat_routes.py`

- [ ] **Step 1: Add preflight before returning `StreamingResponse`**

After `session_id = request.session_id or str(uuid.uuid4())` in `lexi_stream_chat()`:

```python
prechecked_history: Optional[List[Dict[str, Any]]] = None
if request.session_id:
    session_timeout_s = max(
        _HEARTBEAT_INTERVAL_S,
        float(os.getenv("LEXI_STREAM_SESSION_TIMEOUT_SECONDS", "15")),
    )
    try:
        prechecked_history = await asyncio.wait_for(
            _prepare_existing_lexi_session(session_id, current_user, db),
            timeout=session_timeout_s,
        )
    except asyncio.TimeoutError as exc:
        raise HTTPException(
            status_code=503,
            detail="Chat session service is temporarily unavailable",
        ) from exc
```

- [ ] **Step 2: Update `_sse_generator()` session preparation**

Inside `_sse_generator()`, replace the unconditional `session_task = asyncio.create_task(_prepare_session())` flow with:

```python
if prechecked_history is not None:
    history = prechecked_history
else:
    session_task = asyncio.create_task(_prepare_session())
    # keep the existing heartbeat/deadline loop unchanged
```

For the omitted-session path, keep the current "open SSE first, then prepare session with heartbeat" behavior.

- [ ] **Step 3: Run targeted tests**

Run:

```bash
cd ai-service
pytest tests/test_lexi_chat_routes.py -v
```

Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add ai-service/api/routes/lexi_chat.py ai-service/tests/test_lexi_chat_routes.py
git commit -m "fix(ai): enforce Lexi stream session ownership"
```

---

### Task 6: Regression Pass

**Files:**
- No code changes unless tests expose an issue.

- [ ] **Step 1: Run Lexi/session route tests**

```bash
cd ai-service
pytest tests/test_lexi_chat_routes.py tests/test_lexi_session_management.py -v
```

Expected: pass.

- [ ] **Step 2: Run recently affected AI route tests**

```bash
cd ai-service
pytest tests/test_main_lifespan.py tests/test_topic_chat_routes.py tests/test_tts_routes.py tests/test_ollama_router.py tests/test_quota_guard.py -v
```

Expected: pass.

- [ ] **Step 3: Run static checks**

```bash
git diff --check HEAD
python3 -m py_compile ai-service/api/routes/lexi_chat.py
```

Expected: no output from both commands.

- [ ] **Step 4: Manual smoke scenario**

Using two authenticated test users:

1. User A creates a Lexi session.
2. User B calls `/api/v1/lexi/chat` with User A's `session_id`.
3. User B calls `/api/v1/lexi/stream` with User A's `session_id`.
4. Confirm both calls return 403 and do not append messages.
5. User A continues the same session successfully.

- [ ] **Step 5: Final commit**

```bash
git status --short
git add ai-service/api/routes/lexi_chat.py ai-service/tests/test_lexi_chat_routes.py
git commit -m "test(ai): cover Lexi session ownership regressions"
```

Skip this commit if Tasks 3 and 5 already committed all test coverage.
