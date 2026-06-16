import pytest
from unittest.mock import AsyncMock, MagicMock
from datetime import datetime

from api.routes import chat as chat_route
from api.routes import lexi_chat as lexi_route


@pytest.fixture
def mock_chat_db():
    db = MagicMock()

    chat_sessions = MagicMock()
    chat_sessions.find_one = AsyncMock(return_value={"session_id": "s1", "user_id": "u1"})
    chat_sessions.update_one = AsyncMock()

    chat_messages = MagicMock()
    chat_messages.insert_one = AsyncMock()

    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(
        return_value=[
            {"role": "user", "content": "previous user message"},
            {"role": "assistant", "content": "previous assistant message"},
        ]
    )
    chat_messages.find.return_value = cursor

    def get_collection(name):
        if name == "chat_sessions":
            return chat_sessions
        if name == "chat_messages":
            return chat_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection
    return db


@pytest.fixture
def mock_lexi_db():
    db = MagicMock()

    lexi_sessions = MagicMock()
    lexi_sessions.update_one = AsyncMock()

    lexi_messages = MagicMock()
    lexi_messages.insert_many = AsyncMock()

    def get_collection(name):
        if name == "lexi_sessions":
            return lexi_sessions
        if name == "lexi_messages":
            return lexi_messages
        return AsyncMock()

    db.__getitem__.side_effect = get_collection
    return db


@pytest.fixture
def mock_lexi_store(monkeypatch):
    store = MagicMock()
    store.has_session = AsyncMock(return_value=False)
    store.get_messages = AsyncMock(return_value=[])
    store.set_session = AsyncMock()
    store.delete_messages = AsyncMock()
    store.append_message = AsyncMock()
    store.get_session = AsyncMock(return_value=None)
    store.delete_session = AsyncMock()
    store.init_messages = AsyncMock()
    monkeypatch.setattr(lexi_route, "_store", store)
    quota_mock = MagicMock()
    quota_mock.rpm_used = 1
    quota_mock.rpm_limit = 100
    quota_mock.rpd_used = 5
    quota_mock.rpd_limit = 1000
    quota_mock.tpm_used = 100
    quota_mock.tpm_limit = 50000
    quota_mock.tpd_used = 1000
    quota_mock.tpd_limit = 1000000
    monkeypatch.setattr("api.routes.lexi_chat.enforce_user_quota", AsyncMock(return_value=quota_mock))
    monkeypatch.setattr("api.core.redis_client.RedisClient.get_instance", AsyncMock())
    return store


@pytest.mark.asyncio
async def test_chat_send_message_trace_cag_primary_success(monkeypatch, mock_chat_db):
    orchestrator = MagicMock()
    orchestrator.process = AsyncMock(
        return_value={
            "tutor_response": "TraceCAG primary response",
            "metadata": {"models_used": ["groq/qwen3-32b"], "path": "trace-cag"},
        }
    )

    async def _fake_get_orchestrator():
        return orchestrator

    monkeypatch.setattr("api.services.orchestrator.get_orchestrator", _fake_get_orchestrator)

    response = await chat_route.send_message(
        chat_route.SendMessageRequest(session_id="s1", user_id="u1", message="Hello"),
        db=mock_chat_db,
    )

    assert response.response == "TraceCAG primary response"
    assert response.metadata["model_used"] == "groq/qwen3-32b"
    assert response.metadata["trace-cag"]["path"] == "trace-cag"
    assert mock_chat_db["chat_messages"].insert_one.await_count == 2
    mock_chat_db["chat_messages"].find.return_value.sort.assert_called_with("timestamp", -1)

    ai_doc = mock_chat_db["chat_messages"].insert_one.await_args_list[1].args[0]
    assert ai_doc["role"] == "assistant"
    assert ai_doc["model"] == "groq/qwen3-32b"


@pytest.mark.asyncio
async def test_chat_get_session_messages_limit_zero_returns_full_history(mock_chat_db):
    cursor = MagicMock()
    cursor.sort.return_value = cursor
    cursor.limit.return_value = cursor
    cursor.to_list = AsyncMock(
        side_effect=[
            [
                {
                    "role": "user",
                    "content": "hello",
                    "timestamp": datetime.utcnow(),
                },
                {
                    "role": "assistant",
                    "content": "hi",
                    "timestamp": datetime.utcnow(),
                },
            ],
            [],
        ]
    )
    mock_chat_db["chat_messages"].find.return_value = cursor

    result = await chat_route.get_session_messages(
        session_id="s1",
        limit=0,
        db=mock_chat_db,
    )

    assert len(result) == 2
    cursor.limit.assert_not_called()
    assert cursor.to_list.await_count == 1


@pytest.mark.asyncio
async def test_chat_send_message_trace_cag_degraded_retry_success(monkeypatch, mock_chat_db):
    orchestrator = MagicMock()
    orchestrator.process = AsyncMock(
        side_effect=[
            RuntimeError("primary graph failure"),
            {
                "tutor_response": "TraceCAG degraded retry response",
                "metadata": {"models_used": ["groq/qwen3-retry"], "path": "trace-cag_degraded"},
            },
        ]
    )

    async def _fake_get_orchestrator():
        return orchestrator

    monkeypatch.setattr("api.services.orchestrator.get_orchestrator", _fake_get_orchestrator)

    response = await chat_route.send_message(
        chat_route.SendMessageRequest(session_id="s1", user_id="u1", message="Need fallback"),
        db=mock_chat_db,
    )

    assert response.response == "TraceCAG degraded retry response"
    assert response.metadata["model_used"] == "groq/qwen3-retry"
    assert response.metadata["trace-cag"]["fallback_used"] is True
    assert response.metadata["trace-cag"]["retry_mode"] == "trace-cag_degraded"
    assert "primary_error" in response.metadata["trace-cag"]


@pytest.mark.asyncio
async def test_chat_send_message_trace_cag_hard_failure_uses_safe_response(monkeypatch, mock_chat_db):
    orchestrator = MagicMock()
    orchestrator.process = AsyncMock(
        side_effect=[
            RuntimeError("primary graph failure"),
            RuntimeError("degraded graph failure"),
        ]
    )

    async def _fake_get_orchestrator():
        return orchestrator

    monkeypatch.setattr("api.services.orchestrator.get_orchestrator", _fake_get_orchestrator)

    response = await chat_route.send_message(
        chat_route.SendMessageRequest(session_id="s1", user_id="u1", message="Need safe response"),
        db=mock_chat_db,
    )

    assert response.response == chat_route.SAFE_FIXED_RESPONSE
    assert response.metadata["model_used"] == "trace-cag_safe_response"
    assert response.metadata["trace-cag"]["path"] == "safe_fixed_response"
    assert response.metadata["trace-cag"]["fallback_used"] is True


@pytest.mark.asyncio
async def test_lexi_chat_voice_uses_stt_trace_cag_and_tts(
    monkeypatch,
    mock_lexi_db,
    mock_lexi_store,
):
    monkeypatch.setattr(lexi_route, "_transcribe_audio", AsyncMock(return_value="Transcribed from voice"))
    monkeypatch.setattr(lexi_route, "_synthesize_tts", AsyncMock(return_value="FAKE_AUDIO_BASE64"))

    orchestrator = MagicMock()
    orchestrator.process = AsyncMock(
        return_value={
            "tutor_response": "Lexi response from TraceCAG",
            "metadata": {"models_used": ["groq/qwen3-32b"]},
            "linked_concepts": ["past_tense"],
            "scores": {"overall": 0.92},
        }
    )

    async def _fake_get_orchestrator():
        return orchestrator

    monkeypatch.setattr("api.services.orchestrator.get_orchestrator", _fake_get_orchestrator)

    response = await lexi_route.lexi_chat(
        request_context=MagicMock(),
        request=lexi_route.LexiChatRequest(
            user_id="u1",
            message="voice input",
            input_type="voice",
            audio_base64="ZmFrZV9hdWRpbw==",
            enable_tts=True,
            learner_level="B1",
        ),
        db=mock_lexi_db,
        current_user=MagicMock(user_id="u1"),
    )

    assert response.lexi_response == "Lexi response from TraceCAG"
    assert response.audio_base64 == "FAKE_AUDIO_BASE64"
    assert response.metadata["model_used"] == "groq/qwen3-32b"
    assert "stt_complete" in response.metadata["pipeline_steps"]
    assert "trace-cag_complete" in response.metadata["pipeline_steps"]
    assert "tts_complete" in response.metadata["pipeline_steps"]

    first_user_msg = mock_lexi_store.append_message.await_args_list[0].args[1]
    assert first_user_msg["role"] == "user"
    assert first_user_msg["content"] == "Transcribed from voice"


@pytest.mark.asyncio
async def test_lexi_chat_trace_cag_primary_fail_then_degraded_retry_with_tts(
    monkeypatch,
    mock_lexi_db,
    mock_lexi_store,
):
    monkeypatch.setattr(lexi_route, "_synthesize_tts", AsyncMock(return_value="FAKE_AUDIO_BASE64"))

    orchestrator = MagicMock()
    orchestrator.process = AsyncMock(
        side_effect=[
            RuntimeError("primary graph failure"),
            {
                "tutor_response": "Lexi response from degraded TraceCAG",
                "metadata": {"models_used": ["groq/qwen3-retry"], "path": "trace-cag_degraded"},
            },
        ]
    )

    async def _fake_get_orchestrator():
        return orchestrator

    monkeypatch.setattr("api.services.orchestrator.get_orchestrator", _fake_get_orchestrator)

    response = await lexi_route.lexi_chat(
        request_context=MagicMock(),
        request=lexi_route.LexiChatRequest(
            user_id="u1",
            message="text input",
            input_type="text",
            enable_tts=True,
            learner_level="B1",
        ),
        db=mock_lexi_db,
        current_user=MagicMock(user_id="u1"),
    )

    assert response.lexi_response == "Lexi response from degraded TraceCAG"
    assert response.audio_base64 == "FAKE_AUDIO_BASE64"
    assert response.metadata["model_used"] == "groq/qwen3-retry"
    assert "trace-cag_retry_complete" in response.metadata["pipeline_steps"]
    assert "tts_complete" in response.metadata["pipeline_steps"]
    assert response.metadata["trace-cag_metadata"]["fallback_used"] is True
    assert response.metadata["trace-cag_metadata"]["retry_mode"] == "trace-cag_degraded"
