import json
from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.services import exercise_generation as svc

KW = dict(course_title="C", level="A1", unit_title="U", lesson_title="L", lesson_id="lid")


def _lesson() -> list[dict]:
    base = {"explanation": "because"}
    return [
        {**base, "id": "1", "type": "multiple_choice", "ui_type": "multiple_choice",
         "question": "Pick one", "options": ["a", "b"], "correct_answer": "a"},
        {**base, "id": "2", "type": "true_false", "ui_type": "true_or_false",
         "question": "A cup holds tea", "correct_answer": "True"},
        {**base, "id": "3", "type": "fill_blank", "ui_type": "fill_in_the_blank",
         "question": "I drink {blank}", "correct_answer": "tea"},
        {**base, "id": "4", "type": "translate", "ui_type": "short_writing_answer",
         "question": "Write about tea", "correct_answer": "I like tea."},
    ]


def _ok(exercises: list) -> httpx.Response:
    body = {"choices": [{"message": {"content": json.dumps({"exercises": exercises})}}]}
    return httpx.Response(200, json=body)


def _is_verify(request: httpx.Request) -> bool:
    return "QUESTIONS (one JSON" in json.loads(request.content)["messages"][0]["content"]


def _picks(indexes: dict[int, int]) -> httpx.Response:
    body = {"answers": [{"n": n, "index": i} for n, i in indexes.items()]}
    return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(body)}}]})


def _routed(generate, verify):
    def handler(request: httpx.Request) -> httpx.Response:
        return verify(request) if _is_verify(request) else generate(request)

    return handler


def _client(handler) -> httpx.AsyncClient:
    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


@pytest.fixture(autouse=True)
def no_sleep():
    with patch("asyncio.sleep", new_callable=AsyncMock) as sleep:
        yield sleep


@pytest.mark.asyncio
async def test_valid_payload_is_returned_sanitized():
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        return _picks({0: 0, 1: 0}) if _is_verify(request) else _ok(_lesson())

    async with _client(handler) as client:
        result = await svc.generate_lesson_exercises(keys=["k1"], client=client, **KW)

    assert len(result) == 4
    assert result[1]["options"] == ["True", "False"]
    assert calls[0].headers["authorization"] == "Bearer k1"
    assert "reasoning_effort" not in json.loads(calls[0].content)
    assert result.verification == {
        "method": "blind-answer-v1", "status": "verified", "checked": 2, "agreed": 2, "dropped": [],
    }
    blind = json.loads(calls[1].content)["messages"][0]["content"]
    assert "correct_answer" not in blind and "because" not in blind


@pytest.mark.asyncio
async def test_401_is_unavailable_without_retry():
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(1)
        return httpx.Response(401, text="bad key")

    async with _client(handler) as client:
        with pytest.raises(svc.ExerciseGenerationUnavailable):
            await svc.generate_lesson_exercises(keys=["k1"], client=client, **KW)
    assert len(calls) == 1


@pytest.mark.asyncio
async def test_no_keys_is_unavailable():
    with pytest.raises(svc.ExerciseGenerationUnavailable):
        await svc.generate_lesson_exercises(keys=[], **KW)


@pytest.mark.asyncio
async def test_invalid_payloads_fail_after_the_attempt_cap():
    calls = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(1)
        return _ok([{"ui_type": "multiple_choice"}])

    async with _client(handler) as client:
        with pytest.raises(svc.ExerciseGenerationFailed):
            await svc.generate_lesson_exercises(keys=["k"] * 9, client=client, **KW)
    assert len(calls) == svc.ADMIN_ATTEMPT_CAP


@pytest.mark.asyncio
async def test_json_validate_failed_400_retries_then_succeeds():
    replies = [httpx.Response(400, text="json_validate_failed"), _ok(_lesson()), _picks({0: 0, 1: 0})]

    async with _client(lambda request: replies.pop(0)) as client:
        result = await svc.generate_lesson_exercises(keys=["a", "b"], client=client, **KW)
    assert len(result) == 4


def _run(handler, **extra):
    async def go():
        async with _client(handler) as client:
            return await svc.generate_lesson_exercises(keys=["k1"], client=client, **{**KW, **extra})

    return go()


@pytest.mark.asyncio
async def test_wrong_key_is_dropped_and_recorded():
    def verify(request):
        return _picks({0: 1, 1: 0})

    result = await _run(_routed(lambda r: _ok(_lesson()), verify))

    assert [e["id"] for e in result] == ["2", "3", "4"]
    assert result.verification["checked"] == 2
    assert result.verification["agreed"] == 1
    assert result.verification["dropped"] == ["1"]


@pytest.mark.asyncio
async def test_dropping_below_the_floor_retries_then_fails_without_returning_anything():
    generated = []

    def generate(request):
        generated.append(1)
        return _ok(_lesson())

    with pytest.raises(svc.ExerciseGenerationFailed):
        await _run(_routed(generate, lambda r: _picks({0: -1, 1: 1})))
    assert len(generated) == 3


@pytest.mark.asyncio
async def test_survivors_that_are_no_longer_varied_are_refused():
    base = {"explanation": "because"}
    lesson = [
        {**base, "id": "1", "ui_type": "multiple_choice", "type": "multiple_choice",
         "question": "Pick", "options": ["a", "b"], "correct_answer": "a"},
        {**base, "id": "2", "ui_type": "translation_choice", "type": "translate",
         "question": "Pick two", "options": ["a", "b"], "correct_answer": "a"},
        {**base, "id": "3", "ui_type": "fill_in_the_blank", "type": "fill_blank",
         "question": "I drink {blank}", "correct_answer": "tea"},
        {**base, "id": "4", "ui_type": "short_writing_answer", "type": "fill_blank",
         "question": "Write about tea", "correct_answer": "I like tea."},
    ]
    assert svc.lesson_is_varied(lesson)

    with pytest.raises(svc.ExerciseGenerationFailed):
        await _run(_routed(lambda r: _ok(lesson), lambda r: _picks({0: 1, 1: 1})))


@pytest.mark.asyncio
async def test_verification_error_in_admin_mode_returns_an_unverified_draft():
    verify_calls = []

    def verify(request):
        verify_calls.append(1)
        return httpx.Response(500, text="boom")

    result = await _run(_routed(lambda r: _ok(_lesson()), verify))

    assert len(result) == 4
    assert result.verification["status"] == "unverified"
    assert len(verify_calls) == 2


@pytest.mark.asyncio
async def test_verification_error_in_batch_mode_fails_closed():
    with pytest.raises(svc.ExerciseGenerationFailed):
        await _run(
            _routed(lambda r: _ok(_lesson()), lambda r: httpx.Response(200, json={"choices": [{"message": {"content": "not json"}}]})),
            max_attempts=3,
        )


@pytest.mark.asyncio
async def test_unverifiable_types_are_not_sent_to_the_blind_pass():
    sent = []

    def verify(request):
        sent.append(json.loads(request.content)["messages"][0]["content"])
        return _picks({0: 0, 1: 0})

    await _run(_routed(lambda r: _ok(_lesson()), verify))

    assert "Write about tea" not in sent[0] and "I drink" not in sent[0]
    assert "Pick one" in sent[0]


@pytest.mark.asyncio
async def test_verify_exercises_without_choice_items_makes_no_call():
    async def call(prompt: str) -> dict:
        raise AssertionError("no call expected")

    kept, stats = await svc.verify_exercises(
        [_lesson()[2], _lesson()[3]], course_title="C", level="A1", lesson_title="L", call=call
    )
    assert len(kept) == 2 and stats["checked"] == 0
