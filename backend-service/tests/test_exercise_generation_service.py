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
        return _ok(_lesson())

    async with _client(handler) as client:
        result = await svc.generate_lesson_exercises(keys=["k1"], client=client, **KW)

    assert len(result) == 4
    assert result[1]["options"] == ["True", "False"]
    assert calls[0].headers["authorization"] == "Bearer k1"
    assert "reasoning_effort" not in json.loads(calls[0].content)


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
    replies = [httpx.Response(400, text="json_validate_failed"), _ok(_lesson())]

    async with _client(lambda request: replies.pop(0)) as client:
        result = await svc.generate_lesson_exercises(keys=["a", "b"], client=client, **KW)
    assert len(result) == 4
