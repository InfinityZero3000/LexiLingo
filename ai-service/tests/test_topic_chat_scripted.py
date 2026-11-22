"""Scripted (app-suggested) prompts and grounded corrections, JSON route and SSE stream."""

import json
from types import SimpleNamespace
from unittest import mock
from unittest.mock import AsyncMock, MagicMock

import pytest

import api.services.topic_chat_service as svc
from api.routes import topic_chat as topic_route
from api.services.topic_chat_service import TracecagResult, stream_tracecag_topic_message

PROMPTS = ["I need help with a toothache.", "Can you tell me about the cleaning?"]
GOOD = {"span": "I has", "type": "subject_verb_agreement", "correction": "I have", "explanation": "x"}
UNGROUNDED = {"span": "went", "type": "verb_tense", "correction": "go", "explanation": "x"}
ARTICLE = {"span": "a toothache", "type": "article_a_an", "correction": "the toothache", "explanation": "x"}


def _quota():
    return SimpleNamespace(
        rpm_used=1, rpm_limit=60, rpd_used=1, rpd_limit=1000,
        tpm_used=10, tpm_limit=60000, tpd_used=10, tpd_limit=1000000,
    )


def _user(user_id="u1"):
    u = MagicMock()
    u.user_id = user_id
    u.roles = []
    return u


def _make_db(session_doc):
    db = MagicMock()
    sessions = MagicMock()
    sessions.find_one = AsyncMock(return_value=session_doc)
    messages = MagicMock()
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(return_value=[])
    messages.find.return_value = cursor
    db.__getitem__.side_effect = lambda name: (
        messages if name == "chat_messages" else sessions
    )
    return db


# ── helpers ────────────────────────────────────────────────────────────────

def test_is_scripted_prompt_ignores_case_width_spacing_and_trailing_punctuation():
    assert svc.is_scripted_prompt("i need  HELP with a toothache", PROMPTS)
    assert svc.is_scripted_prompt("Ｉ need help with a toothache!", PROMPTS)
    assert not svc.is_scripted_prompt("I has a toothache", PROMPTS)
    assert not svc.is_scripted_prompt("", PROMPTS)
    assert not svc.is_scripted_prompt("anything", None)


@pytest.mark.asyncio
async def test_is_scripted_turn_prefers_stored_prompts_and_falls_back_to_story(monkeypatch):
    stored = {"suggested_prompts": PROMPTS, "story_id": "s1"}
    assert await svc.is_scripted_turn(stored, PROMPTS[0], MagicMock()) is True

    story_service = MagicMock()
    story_service.get_story_by_id = AsyncMock(return_value=SimpleNamespace(suggested_prompts=PROMPTS))
    monkeypatch.setattr(
        "api.services.story_service.StoryService", MagicMock(return_value=story_service)
    )
    legacy = {"story_id": "s1"}
    assert await svc.is_scripted_turn(legacy, PROMPTS[1], MagicMock()) is True

    story_service.get_story_by_id = AsyncMock(side_effect=RuntimeError("mongo down"))
    assert await svc.is_scripted_turn(legacy, PROMPTS[1], MagicMock()) is False


def test_build_turn_hints_scripted_drops_corrections_and_keeps_vocab():
    response = "Of course. [\U0001F4D8 'filling' means material in a tooth.]"

    clean, hints, accepted = svc.build_turn_hints(response, [GOOD], "I has a cold", scripted=True)

    assert accepted == []
    assert hints is not None and hints.grammar_corrections == []
    assert [v.term for v in hints.vocabulary_hints] == ["filling"]
    assert "[" not in clean


def test_build_turn_hints_typed_accepts_only_grounded_errors():
    _, hints, accepted = svc.build_turn_hints("Sure.", [GOOD, ARTICLE], "I has pain", scripted=False)

    assert accepted == [GOOD]
    assert [gc.original for gc in hints.grammar_corrections] == ["I has"]


# ── JSON route ─────────────────────────────────────────────────────────────

async def _send_json_turn(monkeypatch, message, session_extra, diagnosis_errors):
    session_doc = {
        "session_id": "sess-1", "user_id": "u1", "session_type": "topic_based",
        "difficulty_level": "B1", "system_prompt": "You are Dr. Lee.", **session_extra,
    }
    tracecag = AsyncMock(
        return_value=TracecagResult(
            ai_response="Of course.",
            llm_metadata={"provider": "trace-cag"},
            diagnosis_errors=diagnosis_errors,
            trace_result={"concept_ids": []},
        )
    )
    monkeypatch.setattr(topic_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    monkeypatch.setattr(topic_route, "emit_ai_audit_event", AsyncMock())
    monkeypatch.setattr(topic_route, "persist_topic_turn", AsyncMock(return_value="ai-1"))
    monkeypatch.setattr(topic_route, "call_tracecag_with_retry", tracecag)
    with mock.patch("api.core.redis_client.record_learner_errors", autospec=True) as record, \
            mock.patch(
                "api.services.learner_observation_spool.persist_trace_observations",
                autospec=True,
            ) as persist:
        response = await topic_route.send_topic_message(
            MagicMock(headers={}), "sess-1",
            topic_route.TopicChatRequest(user_id="u1", message=message),
            _make_db(session_doc), AsyncMock(), _user("u1"),
        )
    return response, record, persist


@pytest.mark.asyncio
async def test_json_route_scripted_prompt_is_not_corrected_or_recorded(monkeypatch):
    response, record, persist = await _send_json_turn(
        monkeypatch, "I have a toothache.", {"suggested_prompts": ["I have a toothache."]}, [ARTICLE]
    )

    assert not (response.educational_hints or {}).get("grammar_corrections")
    record.assert_not_called()
    persist.assert_not_called()


@pytest.mark.asyncio
async def test_json_route_typed_error_records_accepted_list(monkeypatch):
    response, record, persist = await _send_json_turn(
        monkeypatch, "I has a toothache", {"suggested_prompts": ["I have a toothache."]},
        [GOOD, UNGROUNDED],
    )

    assert response.educational_hints["grammar_corrections"][0]["corrected"] == "I have"
    record.assert_awaited_once_with("u1", [GOOD])
    persist.assert_awaited_once()


@pytest.mark.asyncio
async def test_stream_route_passes_scripted_flag(monkeypatch):
    session_doc = {
        "session_id": "sess-1", "user_id": "u1", "session_type": "topic_based",
        "difficulty_level": "B1", "system_prompt": "x",
        "suggested_prompts": ["I have a toothache."],
    }

    async def fake_stream(**kwargs):
        yield "event: thinking\ndata: {}\n\n"

    stream_mock = MagicMock(side_effect=fake_stream)
    monkeypatch.setattr(topic_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    monkeypatch.setattr(topic_route, "stream_tracecag_topic_message", stream_mock)

    await topic_route.send_topic_message_stream(
        MagicMock(headers={}), "sess-1",
        topic_route.TopicChatRequest(user_id="u1", message="I have a toothache"),
        _make_db(session_doc), AsyncMock(), _user("u1"),
    )

    assert stream_mock.call_args.kwargs["scripted"] is True


# ── SSE stream ─────────────────────────────────────────────────────────────

async def _run_stream_turn(monkeypatch, message, diagnosis_errors, scripted):
    orchestrator = MagicMock()
    orchestrator.pipeline.analyze_for_streaming = AsyncMock(
        return_value={"tutor_response": "", "diagnosis_errors": diagnosis_errors, "user_input": message}
    )
    monkeypatch.setattr(
        "api.services.orchestrator.get_orchestrator", AsyncMock(return_value=orchestrator)
    )
    monkeypatch.setattr("api.core.audit_emitter.emit_ai_audit_event", AsyncMock())
    monkeypatch.setattr(
        "api.services.trace_cag.nodes_v2.build_generation_prompt",
        MagicMock(return_value=("system", [{"role": "user", "content": "hi"}])),
    )

    async def fake_tokens(**kw):
        for tok in ("Sure", "."):
            yield tok

    monkeypatch.setattr("api.services.trace_cag.nodes_v2.stream_llm_tokens", fake_tokens)
    repo = MagicMock()
    repo.insert_messages_bulk = AsyncMock()
    repo.update_session_activity = AsyncMock()

    with mock.patch("api.core.redis_client.record_learner_errors", autospec=True) as record, \
            mock.patch(
                "api.services.learner_observation_spool.persist_trace_observations",
                autospec=True,
            ) as persist:
        events = [
            chunk async for chunk in stream_tracecag_topic_message(
                message=message, session_id="s1", user_id="u1", difficulty_level="B1",
                conversation_history=[], kg_seeds=[], topic_system_prompt="x", repo=repo,
                quota=_quota(), start_time=0.0, request_id="r1", scripted=scripted,
            )
        ]
    done = events[-1]
    assert done.startswith("event: done")
    return json.loads(done.split("data: ", 1)[1]), record, persist


@pytest.mark.asyncio
async def test_stream_scripted_prompt_gets_no_correction_and_no_evidence(monkeypatch):
    done, record, persist = await _run_stream_turn(
        monkeypatch, "I have a toothache.", [ARTICLE], scripted=True
    )

    assert not (done["educational_hints"] or {}).get("grammar_corrections")
    record.assert_not_called()
    persist.assert_not_called()


@pytest.mark.asyncio
async def test_stream_typed_error_is_shown_and_only_accepted_errors_are_recorded(monkeypatch):
    done, record, persist = await _run_stream_turn(
        monkeypatch, "I has a toothache", [GOOD, UNGROUNDED], scripted=False
    )

    cards = done["educational_hints"]["grammar_corrections"]
    assert [(c["original"], c["corrected"], c["error_type"]) for c in cards] == [
        ("I has", "I have", "subject_verb_agreement")
    ]
    record.assert_awaited_once_with("u1", [GOOD])
    persist.assert_awaited_once()
