"""Lexi reads the learner's database profile on every turn, not only when asked."""

import asyncio
from unittest.mock import AsyncMock, MagicMock

import pytest

from api.routes import lexi_chat as lexi_route
from api.services import learner_card as lc
from api.services import lexi_chat_service as svc
from tests.test_lexi_chat_routes import (  # noqa: F401  (fixtures)
    _make_db,
    _quota,
    _user,
    mock_idempotency,
    mock_store,
)

CARD = {
    "display_name": "Thang Nguyen",
    "native_language": "vi",
    "assessed_level": "A2",
    "cefr_level": "B1",
    "goal": "ielts",
    "interest": "cooking",
    "streak_days": 6,
    "skills": {
        "listening": {"score": 38, "exercises": 12},
        "speaking": {"score": 20, "exercises": 1},  # too little evidence to call weakest
    },
    "enrolled_courses": [{"title": "IELTS Foundation", "progress": 35}],
    "suggested_courses": [
        {"course_id": "c2", "title": "Everyday English", "level": "A2"}
    ],
}


def test_card_level_prefers_assessed_and_rejects_non_cefr():
    assert lc.card_level(CARD) == "A2"
    assert lc.card_level({"cefr_level": "b2"}) == "B2"
    assert lc.card_level({"assessed_level": "beginner", "cefr_level": "x"}) is None
    assert lc.card_level(None) is None


def test_profile_brief_has_the_person_not_the_stats():
    brief = lc.render_profile_brief(CARD, "Vietnamese")
    assert "First name: Thang" in brief
    assert "Native language: Vietnamese" in brief
    assert "Currently studying: IELTS Foundation (35% done)" in brief
    assert "Weakest skill so far: listening" in brief
    assert "streak: 6 days" in brief
    assert "ielts" not in brief and "cooking" not in brief  # travel via profile_defaults
    assert "XP" not in brief


def test_profile_brief_skips_email_names_and_is_empty_without_a_card():
    assert "First name" not in lc.render_profile_brief(
        {"display_name": "a.b@mail.com"}, ""
    )
    assert lc.render_profile_brief(None, "Vietnamese") == ""
    assert lc.render_profile_brief({}, "") == ""


def test_profile_defaults_carry_level_goal_interest_only_when_present():
    assert lc.profile_defaults(CARD) == {
        "level": "A2",
        "goal": "ielts",
        "interest": "cooking",
    }
    assert lc.profile_defaults({"goal": " "}) == {}


@pytest.mark.asyncio
async def test_ordinary_turn_gets_profile_but_not_the_fact_block(monkeypatch):
    monkeypatch.setattr(lc, "get_learner_card", AsyncMock(return_value=CARD))

    ctx = await svc._resolve_learner_card("u1", "I went to the market")

    assert ctx.facts == "" and ctx.courses == ()
    assert ctx.profile["level"] == "A2"
    assert ctx.profile["goal"] == "ielts"
    assert "First name: Thang" in ctx.profile["profile_brief"]


@pytest.mark.asyncio
async def test_question_about_courses_also_gets_facts_and_real_course_rows(monkeypatch):
    monkeypatch.setattr(lc, "get_learner_card", AsyncMock(return_value=CARD))

    ctx = await svc._resolve_learner_card("u1", "Which courses are good for me?")

    assert "Courses matching their level: Everyday English" in ctx.facts
    assert [c.course_id for c in ctx.courses] == ["c2"]


@pytest.mark.asyncio
async def test_slow_card_never_stalls_an_ordinary_turn(monkeypatch):
    async def slow(_user_id):
        await asyncio.sleep(1.0)
        return CARD

    monkeypatch.setattr(lc, "get_learner_card", slow)
    monkeypatch.setattr(svc, "_PROFILE_WAIT_SECONDS", 0.05)

    started = asyncio.get_running_loop().time()
    ctx = await svc._resolve_learner_card("u1", "I went to the market")

    assert asyncio.get_running_loop().time() - started < 0.5
    assert ctx == svc._CardContext()


@pytest.mark.asyncio
async def test_unavailable_card_is_silent_for_chat_but_explicit_for_questions(monkeypatch):
    monkeypatch.setattr(lc, "get_learner_card", AsyncMock(return_value=None))

    assert await svc._resolve_learner_card("u1", "Hello there") == svc._CardContext()
    ctx = await svc._resolve_learner_card("u1", "Can you give me some courses?")
    assert "Never claim the app has no courses" in ctx.facts


async def _profile_sent_to_orchestrator(monkeypatch, mock_store, mock_idempotency, message):
    monkeypatch.setattr(lexi_route, "enforce_user_scope", lambda cu, uid: uid)
    monkeypatch.setattr(lexi_route, "enforce_user_quota", AsyncMock(return_value=_quota()))
    monkeypatch.setattr(lexi_route, "emit_ai_audit_event", AsyncMock())
    monkeypatch.setattr(lc, "get_learner_card", AsyncMock(return_value=CARD))
    orchestrator = MagicMock()
    orchestrator.process = AsyncMock(
        return_value={"tutor_response": "ok", "metadata": {}}
    )
    monkeypatch.setattr(
        "api.services.orchestrator.get_orchestrator", AsyncMock(return_value=orchestrator)
    )
    request_ctx = MagicMock()
    request_ctx.headers = {"X-Request-Id": "req"}
    await lexi_route.lexi_chat(
        request_context=request_ctx,
        # the app always sends B1; the database says A2
        request=lexi_route.LexiChatRequest(
            user_id="u1", message=message, learner_level="B1"
        ),
        x_idempotency_key=None,
        db=_make_db(),
        current_user=_user(),
    )
    return orchestrator.process.call_args.kwargs


@pytest.mark.asyncio
async def test_database_level_beats_the_fixed_level_the_app_sends(
    mock_store, mock_idempotency, monkeypatch
):
    kwargs = await _profile_sent_to_orchestrator(
        monkeypatch, mock_store, mock_idempotency, "I went to the market"
    )
    profile = kwargs["learner_profile"]
    assert profile["level"] == "A2"
    assert "First name: Thang" in profile["profile_brief"]
    assert "learner_facts" not in profile
    # an ordinary turn keeps the response cache; only personal facts age
    assert "cache_policy" not in kwargs


@pytest.mark.asyncio
async def test_personal_question_turns_the_cache_off(
    mock_store, mock_idempotency, monkeypatch
):
    kwargs = await _profile_sent_to_orchestrator(
        monkeypatch, mock_store, mock_idempotency, "What is my level?"
    )
    assert "learner_facts" in kwargs["learner_profile"]
    assert kwargs["cache_policy"] == "off"
