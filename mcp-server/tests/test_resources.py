import json

import pytest

from resources import conversation, learner_profile, lesson_context
from utils.api_client import UpstreamServiceError


@pytest.mark.asyncio
async def test_learner_profile_uses_authenticated_backend_data(monkeypatch):
    async def fake_call(method, path, **kwargs):
        if path == "/api/v1/users/me":
            return {
                "id": "user-1",
                "level": "B2",
                "native_language": "vi",
                "target_language": "en",
            }
        assert path == "/api/v1/users/me/stats"
        return {
            "data": {
                "lessons_completed": 12,
                "total_study_time": 345,
                "current_streak": 7,
            }
        }

    monkeypatch.setattr(learner_profile, "call_backend_service", fake_call)

    payload = json.loads(await learner_profile.get("user-1"))

    assert payload["level"] == "B2"
    assert payload["progress"]["lessons_completed"] == 12
    assert payload["source"]["service"] == "backend-service"
    assert payload["freshness"]["status"] == "fresh"
    assert payload["error"] is None


@pytest.mark.asyncio
async def test_conversation_falls_back_to_topic_only_on_not_found(monkeypatch):
    calls = []

    async def fake_call(method, path, **kwargs):
        calls.append(path)
        if path.startswith("/api/v1/lexi/"):
            raise UpstreamServiceError("ai-service", 404, False)
        return {"messages": [{"role": "user", "content": "hello"}]}

    monkeypatch.setattr(conversation, "call_ai_service", fake_call)

    payload = json.loads(await conversation.get("session-1"))

    assert calls == [
        "/api/v1/lexi/sessions/session-1/messages?full=true",
        "/api/v1/topics/topic-sessions/session-1/messages",
    ]
    assert payload["messages"][0]["content"] == "hello"
    assert payload["error"] is None


@pytest.mark.asyncio
async def test_conversation_does_not_bypass_forbidden(monkeypatch):
    async def fake_call(method, path, **kwargs):
        raise UpstreamServiceError("ai-service", 403, False)

    monkeypatch.setattr(conversation, "call_ai_service", fake_call)

    payload = json.loads(await conversation.get("session-1"))

    assert payload["messages"] == []
    assert payload["error"]["code"] == "UPSTREAM_FORBIDDEN"
    assert payload["error"]["retryable"] is False


@pytest.mark.asyncio
async def test_lesson_context_filters_answer_material(monkeypatch):
    async def fake_call(method, path, **kwargs):
        assert path == "/api/v1/learning/lessons/lesson-1/context"
        return {
            "data": {
                "id": "lesson-1",
                "title": "Greetings",
                "exercises": [
                    {
                        "question": "Choose hello",
                        "correct_answer": "hello",
                        "options": [
                            {"text": "hello", "is_correct": True},
                            {"text": "bye", "is_correct": False},
                        ],
                    }
                ],
            }
        }

    monkeypatch.setattr(lesson_context, "call_backend_service", fake_call)

    payload = json.loads(await lesson_context.get("lesson-1"))
    serialized = json.dumps(payload)

    assert payload["title"] == "Greetings"
    assert "correct_answer" not in serialized
    assert "is_correct" not in serialized
    assert payload["source"]["store"] == "postgresql"
