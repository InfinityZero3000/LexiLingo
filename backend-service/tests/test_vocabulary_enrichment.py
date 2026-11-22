"""Vocabulary auto-enrichment: Groq call, per-item fill, retry, sweep, quick-save enqueue, corpus export."""

import json
import uuid
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from sqlalchemy import select

from app.core.config import settings
from app.models.vocabulary import VocabularyItem
from app.routes import vocabulary as vocabulary_routes
from app.services import reference_content, vocabulary_translation as vt
from app.tasks import vocabulary_enrichment as tasks
from tests.test_vocabulary_routes import (  # noqa: F401 - fixtures
    BASE,
    _make_mock_user_vocab,
    _make_mock_vocab_item,
    auth_client,
)

DEF = "to pull or move something with force"
FULL_GLOSS = {"vi": "kéo lê", "es": "arrastrar", "fr": "traîner", "ja": "引きずる", "ko": "끌다", "zh": "拖"}
FULL_DEFS = {
    "vi": "kéo hoặc di chuyển vật gì bằng sức",
    "es": "tirar o mover algo con fuerza",
    "fr": "tirer ou déplacer quelque chose avec force",
    "ja": "力を入れて何かを引く、動かす",
    "ko": "힘을 들여 무언가를 끌거나 옮기다",
    "zh": "用力拉或移动某物",
}


def _complete() -> dict:
    return {**FULL_GLOSS, "definitions": dict(FULL_DEFS), "examples": ["The dog dragged him."]}


def groq_body(item_id: str, **fields) -> dict:
    """Shaped like Groq's chat completion: the JSON answer is a string in choices[0].message.content."""
    answer = {
        "items": [
            {
                "id": item_id,
                "definition": "",
                "example": "The dog dragged him.",
                "gloss": FULL_GLOSS,
                "definition_translation": FULL_DEFS,
                **fields,
            }
        ]
    }
    return {
        "id": "chatcmpl-1",
        "object": "chat.completion",
        "model": "qwen/qwen3.8-27b",
        "choices": [
            {
                "index": 0,
                "finish_reason": "stop",
                "message": {"role": "assistant", "content": json.dumps(answer, ensure_ascii=False)},
            }
        ],
        "usage": {"prompt_tokens": 400, "completion_tokens": 210, "total_tokens": 610},
    }


def mock_groq(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


@pytest.fixture
def memory_backend(monkeypatch):
    """Eager task runs build a result backend; keep it off the .env Redis."""
    from celery.app.base import Celery
    from celery.backends.cache import CacheBackend

    from app.core.celery_app import celery_app

    backend = CacheBackend(app=celery_app, backend="memory://")
    monkeypatch.setattr(Celery, "backend", property(lambda self: backend))


@pytest.fixture(autouse=True)
def _groq_state(monkeypatch):
    monkeypatch.setattr(settings, "GROQ_API_KEYS", "key-a,key-b")
    monkeypatch.setattr(settings, "VOCAB_AUTO_TRANSLATE_ENABLED", True)
    monkeypatch.setattr(vt, "_key_cooldown", {})
    monkeypatch.setattr(vt, "_key_cursor", 0)


async def _add(db, word="drag", definition=DEF, translation=None) -> VocabularyItem:
    item = VocabularyItem(
        word=word, definition=definition, translation=translation,
        part_of_speech="verb", difficulty_level="A1",
    )
    db.add(item)
    await db.commit()
    return item


async def _translation(db, item_id):
    await db.rollback()
    return (await db.execute(select(VocabularyItem.translation).where(VocabularyItem.id == item_id))).scalar_one()


class _SameSession:
    def __init__(self, session):
        self.session = session

    async def __aenter__(self):
        return self.session

    async def __aexit__(self, *exc):
        return False


# ---- Groq request ---------------------------------------------------------


def test_payload_pins_reasoning_off_for_qwen():
    payload = vt.build_payload([{"id": "1", "word": "x", "part_of_speech": "noun", "definition": "", "translation": {}}])
    assert payload["model"] == "qwen/qwen3.8-27b"
    assert payload["reasoning_effort"] == "none"
    assert payload["response_format"] == {"type": "json_object"}


@pytest.mark.asyncio
async def test_request_translations_parses_real_shape_and_sends_key():
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["auth"] = request.headers["authorization"]
        seen["body"] = json.loads(request.content)
        return httpx.Response(200, json=groq_body("abc"))

    async with mock_groq(handler) as client:
        out = await vt.request_translations(client, [{"id": "abc", "word": "drag", "part_of_speech": "verb",
                                                       "definition": DEF, "translation": {}}])
    assert out["abc"]["gloss"]["ja"] == "引きずる"
    assert seen["auth"] == "Bearer key-a"
    assert seen["body"]["reasoning_effort"] == "none"


@pytest.mark.asyncio
async def test_429_rotates_to_the_next_key_then_raises_retryable():
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request.headers["authorization"])
        return httpx.Response(429, text="Rate limit reached. Please try again in 1m30s.")

    row = {"id": "abc", "word": "drag", "part_of_speech": "verb", "definition": DEF, "translation": {}}
    async with mock_groq(handler) as client:
        with pytest.raises(vt.GroqRetryable) as exc:
            await vt.request_translations(client, [row])
    assert calls == ["Bearer key-a", "Bearer key-b"]
    assert exc.value.retry_after == 90


@pytest.mark.asyncio
async def test_auth_rejection_is_fatal_and_5xx_is_retryable():
    row = {"id": "abc", "word": "drag", "part_of_speech": "verb", "definition": DEF, "translation": {}}
    async with mock_groq(lambda r: httpx.Response(401, text="bad key")) as client:
        with pytest.raises(vt.GroqFatal):
            await vt.request_translations(client, [row])
    async with mock_groq(lambda r: httpx.Response(503, text="down")) as client:
        with pytest.raises(vt.GroqRetryable):
            await vt.request_translations(client, [row])


# ---- enrich_item ----------------------------------------------------------


@pytest.mark.asyncio
async def test_enrich_fills_missing_and_keeps_admin_values(db_session):
    item = await _add(db_session, translation={"vi": "kéo (admin)", "examples": ["Keep me."]})

    async with mock_groq(lambda r: httpx.Response(200, json=groq_body(str(item.id), example="Replaced?"))) as client:
        outcome = await vt.enrich_item(db_session, item.id, client)

    assert outcome.status == "enriched"
    tr = await _translation(db_session, item.id)
    assert tr["vi"] == "kéo (admin)"
    assert tr["examples"] == ["Keep me."]
    assert {k: tr[k] for k in ("es", "fr", "ja", "ko", "zh")} == {k: FULL_GLOSS[k] for k in ("es", "fr", "ja", "ko", "zh")}
    assert tr["definitions"] == FULL_DEFS


@pytest.mark.asyncio
async def test_enrich_replaces_placeholder_definition(db_session):
    item = await _add(db_session, word="breathtaking", definition="A user-saved word: breathtaking",
                      translation={"vi": "ngoạn mục"})
    body = groq_body(str(item.id), definition="extremely beautiful or surprising")
    async with mock_groq(lambda r: httpx.Response(200, json=body)) as client:
        await vt.enrich_item(db_session, item.id, client)
    await db_session.rollback()
    stored = (await db_session.execute(select(VocabularyItem.definition).where(VocabularyItem.id == item.id))).scalar_one()
    assert stored == "extremely beautiful or surprising"


@pytest.mark.asyncio
async def test_complete_item_is_a_noop_without_calling_groq(db_session):
    item = await _add(db_session, translation=_complete())
    called = []
    async with mock_groq(lambda r: called.append(r) or httpx.Response(500)) as client:
        outcome = await vt.enrich_item(db_session, item.id, client)
    assert outcome.status == "complete"
    assert called == []


@pytest.mark.asyncio
async def test_broken_ja_value_is_redone(db_session):
    broken = _complete()
    broken["ja"] = "pull"  # Latin copy in a CJK slot
    item = await _add(db_session, word="tug", translation=broken)
    async with mock_groq(lambda r: httpx.Response(200, json=groq_body(str(item.id)))) as client:
        outcome = await vt.enrich_item(db_session, item.id, client)
    assert outcome.status == "enriched"
    assert (await _translation(db_session, item.id))["ja"] == "引きずる"


@pytest.mark.asyncio
async def test_unusable_answer_is_partial_and_changes_no_value(db_session):
    item = await _add(db_session, word="tug", translation={"vi": "kéo"})
    bad = groq_body(str(item.id), gloss={**FULL_GLOSS, "ja": "pull"}, definition_translation={})
    async with mock_groq(lambda r: httpx.Response(200, json=bad)) as client:
        outcome = await vt.enrich_item(db_session, item.id, client)
    assert outcome.status == "partial"
    assert "gloss.ja" in outcome.gaps
    assert "ja" not in await _translation(db_session, item.id)


# ---- tasks ----------------------------------------------------------------


@pytest.mark.asyncio
async def test_enrich_one_maps_groq_errors(db_session, monkeypatch):
    monkeypatch.setattr(tasks, "AsyncSessionLocal", lambda: _SameSession(db_session))
    monkeypatch.setattr(tasks, "close_db", AsyncMock())
    with patch.object(tasks, "enrich_item", autospec=True) as enrich:
        enrich.side_effect = vt.GroqRetryable("429", retry_after=300)
        assert await tasks._enrich_one(str(uuid.uuid4())) == ("retry", 300)
        enrich.side_effect = vt.GroqFatal("401")
        assert await tasks._enrich_one(str(uuid.uuid4())) == ("failed", None)


def test_retry_countdown_is_exponential_capped_and_honours_hint():
    assert [tasks.retry_countdown(n) for n in range(5)] == [60, 120, 240, 480, 960]
    assert tasks.retry_countdown(5) == 1800
    assert tasks.retry_countdown(0, hint=500) == 500
    assert tasks.retry_countdown(0, hint=99999) == 1800


def test_task_retries_with_backoff_then_gives_up(memory_backend):
    with patch.object(tasks, "_enrich_one", autospec=True), \
         patch.object(tasks.asyncio, "run", side_effect=lambda coro: (coro.close(), ("retry", None))[1]) as run:
        result = tasks.enrich_vocabulary_item.apply(args=[str(uuid.uuid4())])
    assert result.result == {"status": "gave_up"}
    assert run.call_count == tasks.MAX_RETRIES + 1


def test_task_is_disabled_by_the_flag(monkeypatch, memory_backend):
    monkeypatch.setattr(settings, "VOCAB_AUTO_TRANSLATE_ENABLED", False)
    with patch.object(tasks.asyncio, "run", autospec=True) as run:
        assert tasks.enrich_vocabulary_item.apply(args=["x"]).result == {"status": "disabled"}
        assert tasks.enrich_incomplete_vocabulary.apply().result == {"status": "disabled"}
    run.assert_not_called()


def test_task_never_raises_on_unexpected_error(memory_backend):
    with patch.object(tasks, "_enrich_one", autospec=True), \
         patch.object(tasks.asyncio, "run", side_effect=RuntimeError("boom")):
        assert tasks.enrich_vocabulary_item.apply(args=["x"]).result == {"status": "failed"}


@pytest.mark.asyncio
async def test_sweep_picks_only_incomplete_oldest_first(db_session, monkeypatch):
    done = await _add(db_session, word="done", translation=_complete())
    older = await _add(db_session, word="older", translation={"vi": "a"})
    newer = await _add(db_session, word="newer", translation={"vi": "b"})
    ids = await vt.find_incomplete_ids(db_session, limit=10)
    assert done.id not in ids
    assert set(ids) == {older.id, newer.id}
    assert ids == sorted(ids, key=lambda i: {older.id: 0, newer.id: 1}[i])
    assert await vt.find_incomplete_ids(db_session, limit=1) == [ids[0]]


@pytest.mark.asyncio
async def test_sweep_enriches_batch_and_stops_when_rate_limited(db_session, monkeypatch):
    monkeypatch.setattr(tasks, "AsyncSessionLocal", lambda: _SameSession(db_session))
    monkeypatch.setattr(tasks, "close_db", AsyncMock())
    a = await _add(db_session, word="alpha", translation={"vi": "a"})
    b = await _add(db_session, word="beta", translation={"vi": "b"})
    a_id, b_id = str(a.id), str(b.id)
    real_client = httpx.AsyncClient
    monkeypatch.setattr(tasks.httpx, "AsyncClient", lambda: real_client(transport=httpx.MockTransport(
        lambda r: httpx.Response(200, json=groq_body(a_id)) if a_id in r.content.decode()
        else httpx.Response(429, text="try again in 5s")
    )))
    stats = await tasks._sweep(limit=5, delay=0)
    assert stats["candidates"] == 2
    assert stats["enriched"] == 1
    assert stats["stopped"] == "every Groq key is rate limited"
    assert (await _translation(db_session, uuid.UUID(a_id)))["ja"] == "引きずる"
    assert "ja" not in await _translation(db_session, uuid.UUID(b_id))


# ---- quick-save enqueue ---------------------------------------------------


def _fake_item(translation):
    item = MagicMock()
    item.id = uuid.uuid4()
    item.word = "drag"
    item.definition = DEF
    item.translation = translation
    item.part_of_speech = "verb"
    return item


class FakeRedis:
    def __init__(self):
        self.store: dict[str, str] = {}

    async def set(self, key, value, nx=False, ex=None):
        if nx and key in self.store:
            return None
        self.store[key] = value
        return True

    async def delete(self, key):
        return 1 if self.store.pop(key, None) is not None else 0


@pytest.fixture
def fake_redis():
    client = FakeRedis()
    with patch("app.services.vocabulary_translation.get_redis", new=AsyncMock(return_value=client)):
        yield client


@pytest.mark.asyncio
async def test_schedule_enqueues_incomplete_once_and_skips_complete(fake_redis):
    with patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True) as queued:
        assert await vt.schedule_enrichment(_fake_item({"vi": "kéo"})) is True
        assert queued.call_count == 1
        assert await vt.schedule_enrichment(_fake_item(_complete())) is False
        assert queued.call_count == 1


@pytest.mark.asyncio
async def test_schedule_is_off_when_flag_off(monkeypatch, fake_redis):
    monkeypatch.setattr(settings, "VOCAB_AUTO_TRANSLATE_ENABLED", False)
    with patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True) as queued:
        assert await vt.schedule_enrichment(_fake_item({"vi": "kéo"})) is False
    queued.assert_not_called()


@pytest.mark.asyncio
async def test_broker_outage_does_not_raise_and_frees_the_marker(fake_redis):
    item = _fake_item({"vi": "kéo"})
    with patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True, side_effect=OSError("redis down")):
        assert await vt.schedule_enrichment(item) is False
    assert vt.pending_key(item.id) not in fake_redis.store


@pytest.mark.asyncio
async def test_same_item_is_queued_once_until_released(fake_redis):
    item = _fake_item({"vi": "kéo"})
    with patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True) as queued:
        assert await vt.schedule_enrichment(item) is True
        assert await vt.schedule_enrichment(item) is False
        assert await vt.schedule_enrichment(item) is False
        assert queued.call_count == 1
        await vt.release_pending(item.id)
        assert await vt.schedule_enrichment(item) is True
        assert queued.call_count == 2


@pytest.mark.asyncio
async def test_redis_down_still_enqueues():
    item = _fake_item({"vi": "kéo"})
    with patch("app.services.vocabulary_translation.get_redis", new=AsyncMock(side_effect=OSError("no redis"))), \
         patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True) as queued:
        assert await vt.schedule_enrichment(item) is True
        assert await vt.schedule_enrichment(item) is True
    assert queued.call_count == 2


@pytest.mark.asyncio
async def test_redis_not_connected_still_enqueues():
    with patch("app.services.vocabulary_translation.get_redis", new=AsyncMock(return_value=None)), \
         patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True) as queued:
        assert await vt.schedule_enrichment(_fake_item({"vi": "kéo"})) is True
    assert queued.call_count == 1


def test_task_releases_the_marker_when_finished():
    release = AsyncMock()
    with patch.object(tasks, "_enrich_one", new=AsyncMock(return_value=("enriched", None))), \
         patch.object(tasks, "release_pending", new=release):
        assert tasks.enrich_vocabulary_item.run("abc") == {"status": "enriched"}
    release.assert_awaited_once_with("abc")


def test_task_keeps_the_marker_while_a_retry_is_pending():
    release = AsyncMock()
    with patch.object(tasks, "_enrich_one", new=AsyncMock(return_value=("retry", None))), \
         patch.object(tasks, "release_pending", new=release), \
         patch.object(tasks.enrich_vocabulary_item, "retry", side_effect=RuntimeError("retry")):
        with pytest.raises(RuntimeError):
            tasks.enrich_vocabulary_item.run("abc")
    release.assert_not_awaited()


@pytest.mark.asyncio
async def test_quick_save_new_word_enqueues_enrichment_once(auth_client):
    client, _, _, _ = auth_client
    item = _make_mock_vocab_item()
    item.translation = {"vi": "sự nhất quán"}
    with patch("app.crud.vocabulary.vocabulary_crud.find_vocabulary_by_word", new=AsyncMock(return_value=None)), \
         patch("app.routes.vocabulary._lookup_word", new=AsyncMock(return_value={"definition": "d", "translation": "t"})), \
         patch("app.crud.vocabulary.vocabulary_crud.create_vocabulary_item", new=AsyncMock(return_value=item)), \
         patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary", new=AsyncMock(return_value=None)), \
         patch("app.crud.vocabulary.vocabulary_crud.add_to_collection", new=AsyncMock(return_value=_make_mock_user_vocab())), \
         patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True) as queued:
        response = await client.post(f"{BASE}/collection/quick-save", json={"word": "consistency"})
    assert response.status_code == 201
    queued.assert_called_once()
    assert queued.call_args.kwargs["args"] == [str(item.id)]


@pytest.mark.asyncio
async def test_quick_save_complete_item_does_not_enqueue(auth_client):
    client, _, _, _ = auth_client
    item = _make_mock_vocab_item()
    item.definition = DEF
    item.translation = _complete()
    with patch("app.crud.vocabulary.vocabulary_crud.find_vocabulary_by_word", new=AsyncMock(return_value=item)), \
         patch("app.crud.vocabulary.vocabulary_crud.fill_placeholder_item", new=AsyncMock(return_value=item)), \
         patch("app.crud.vocabulary.vocabulary_crud.get_user_vocabulary", new=AsyncMock(return_value=None)), \
         patch("app.crud.vocabulary.vocabulary_crud.add_to_collection", new=AsyncMock(return_value=_make_mock_user_vocab())), \
         patch.object(tasks.enrich_vocabulary_item, "apply_async", autospec=True) as queued:
        response = await client.post(f"{BASE}/collection/quick-save", json={"word": "drag"})
    assert response.status_code == 201
    queued.assert_not_called()


# ---- corpus export --------------------------------------------------------

FILES = {"vocabulary/manifest.json": "{}\n", "questions/question_bank.json": "[]\n"}


def test_publish_export_rotates_previous_and_cleans_staging(tmp_path):
    reference_content.publish_export({**FILES, "vocabulary/v.json": "one\n"}, tmp_path, {"n": 1})
    reference_content.publish_export({**FILES, "vocabulary/v.json": "two\n"}, tmp_path, {"n": 2})
    assert (tmp_path / "vocabulary/v.json").read_text() == "two\n"
    assert (tmp_path / "previous/vocabulary/v.json").read_text() == "one\n"
    assert json.loads((tmp_path / "export.json").read_text())["n"] == 2
    assert json.loads((tmp_path / "previous/export.json").read_text())["n"] == 1
    assert not [p for p in tmp_path.iterdir() if p.name.startswith(".staging")]


def test_failed_build_leaves_live_export_untouched(tmp_path):
    reference_content.publish_export({**FILES, "vocabulary/v.json": "good\n"}, tmp_path, {"n": 1})
    with patch.object(reference_content, "write_files", autospec=True, side_effect=OSError("disk full")):
        with pytest.raises(OSError):
            reference_content.publish_export(FILES, tmp_path, {"n": 2})
    assert (tmp_path / "vocabulary/v.json").read_text() == "good\n"
    assert not (tmp_path / "previous").exists() or not list((tmp_path / "previous").iterdir())
    assert not [p for p in tmp_path.iterdir() if p.name.startswith(".staging")]


def test_export_task_is_a_noop_when_dir_unset(monkeypatch, memory_backend):
    monkeypatch.setattr(settings, "REFERENCE_CORPUS_DIR", "")
    with patch.object(tasks.asyncio, "run", autospec=True) as run:
        assert tasks.export_reference_corpus.apply().result == {"status": "skipped"}
    run.assert_not_called()


@pytest.mark.asyncio
async def test_export_writes_corpus_with_counts(db_engine, db_session, tmp_path, monkeypatch):
    await _add(db_session, word="drag", translation=_complete())
    monkeypatch.setattr(tasks, "engine", db_engine)
    monkeypatch.setattr(tasks, "close_db", AsyncMock())
    result = await tasks._export(tmp_path)
    assert result["status"] == "exported"
    assert result["counts"]["vocabulary_items"] == 1
    manifest = json.loads((tmp_path / "vocabulary/manifest.json").read_text())
    assert manifest["counts"]["total"] == 1
    assert json.loads((tmp_path / "export.json").read_text())["counts"]["vocabulary_items"] == 1


def test_new_tasks_are_scheduled_in_beat():
    from app.core.celery_app import celery_app

    scheduled = {e["task"] for e in celery_app.conf.beat_schedule.values()}
    assert "app.tasks.vocabulary_enrichment.enrich_incomplete_vocabulary" in scheduled
    assert "app.tasks.vocabulary_enrichment.export_reference_corpus" in scheduled
