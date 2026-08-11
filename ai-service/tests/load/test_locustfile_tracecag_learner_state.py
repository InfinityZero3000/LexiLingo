import json
import importlib
import sys
from types import SimpleNamespace
from types import ModuleType
from unittest.mock import MagicMock, call

import pytest


class _Hook:
    def add_listener(self, function):
        return function


locust = ModuleType("locust")
locust.HttpUser = object
locust.between = lambda *_args: None
locust.task = lambda *_args: (lambda function: function)
locust.events = SimpleNamespace(
    init_command_line_parser=_Hook(),
    test_start=_Hook(),
    test_stop=_Hook(),
    request=SimpleNamespace(fire=MagicMock()),
)
sys.modules.setdefault("locust", locust)

harness = importlib.import_module("tests.load.locustfile_tracecag_learner_state")


@pytest.fixture(autouse=True)
def reset_harness_globals():
    harness._IDENTITIES = []
    harness._IDENTITY_INDEX = 0
    harness._INITIALIZATIONS_STARTED = 0
    harness._INITIALIZATIONS_COMPLETED = 0
    harness._CANARIES.clear()
    yield
    harness._IDENTITIES = []
    harness._IDENTITY_INDEX = 0
    harness._INITIALIZATIONS_STARTED = 0
    harness._INITIALIZATIONS_COMPLETED = 0
    harness._CANARIES.clear()


def test_load_identities_reads_jsonl_and_ignores_blank_lines(tmp_path):
    source = tmp_path / "identities.jsonl"
    source.write_text(
        "\n".join(
            [
                json.dumps({"token": " token-a ", "user_id": " user-a "}),
                "",
                json.dumps({"token": "token-b", "user_id": "user-b"}),
            ]
        )
    )
    source.chmod(0o600)

    assert harness._load_identities(str(source)) == [
        ("token-a", "user-a"),
        ("token-b", "user-b"),
    ]


@pytest.mark.parametrize(
    "record",
    [{"user_id": "user-a"}, {"token": "token-a"}, {"token": "", "user_id": ""}],
)
def test_load_identities_rejects_missing_token_or_user_id(tmp_path, record):
    source = tmp_path / "identities.jsonl"
    source.write_text(json.dumps(record) + "\n")
    source.chmod(0o600)

    with pytest.raises(ValueError, match="requires token and user_id"):
        harness._load_identities(str(source))


@pytest.mark.parametrize(
    ("records", "message"),
    [
        (
            [
                {"token": "token-a", "user_id": "user-a"},
                {"token": "token-b", "user_id": "user-a"},
            ],
            "duplicate user_id on identity line 2",
        ),
        (
            [
                {"token": "token-a", "user_id": "user-a"},
                {"token": "token-a", "user_id": "user-b"},
            ],
            "duplicate token on identity line 2",
        ),
    ],
)
def test_load_identities_rejects_duplicate_users_and_tokens(
    tmp_path, records, message
):
    source = tmp_path / "identities.jsonl"
    source.write_text("\n".join(json.dumps(record) for record in records) + "\n")
    source.chmod(0o600)

    with pytest.raises(ValueError, match=message):
        harness._load_identities(str(source))


def test_load_identity_pool_rejects_pool_smaller_than_requested_users(tmp_path):
    source = tmp_path / "identities.jsonl"
    source.write_text(json.dumps({"token": "token-a", "user_id": "user-a"}) + "\n")
    source.chmod(0o600)
    environment = SimpleNamespace(
        parsed_options=SimpleNamespace(tokens_file=str(source), num_users=2)
    )

    with pytest.raises(RuntimeError, match="1 entries for 2 users"):
        harness.load_identity_pool(environment)


def test_load_identity_pool_rejects_shared_single_identity_for_multiple_users():
    environment = SimpleNamespace(
        parsed_options=SimpleNamespace(
            tokens_file="", token="shared", user_id="shared-user", num_users=2
        )
    )

    with pytest.raises(RuntimeError, match="unique identity"):
        harness.load_identity_pool(environment)


def test_on_start_uses_assigned_identity_and_created_session(monkeypatch):
    harness._IDENTITIES = [("token-a", "user-a")]
    monkeypatch.setattr(
        harness.uuid, "uuid4", lambda: SimpleNamespace(hex="abc123def4567890")
    )
    session_response = MagicMock(status_code=201)
    session_response.json.return_value = {"session_id": "session-created"}
    seed_response = MagicMock(status_code=200, text='{"metadata": {}}')
    seed_response.json.return_value = {"metadata": {}}
    seed_context = MagicMock()
    seed_context.__enter__.return_value = seed_response
    isolation_response = MagicMock(
        status_code=200,
        text='{"response": "LXabc123def456", "metadata": {}}',
    )
    isolation_response.json.return_value = {"metadata": {}}
    isolation_context = MagicMock()
    isolation_context.__enter__.return_value = isolation_response
    client = MagicMock()
    client.post.side_effect = [session_response, seed_context, isolation_context]
    user = object.__new__(harness.TraceCAGLearnerUser)
    user.client = client
    user.environment = SimpleNamespace(
        parsed_options=SimpleNamespace(token="fallback", user_id="fallback-user")
    )

    user.on_start()

    assert user.token == "token-a"
    assert user.user_id == "user-a"
    assert user.session_id == "session-created"
    assert client.post.call_args_list[0] == call(
        "/api/v1/chat/sessions",
        json={"user_id": "user-a", "title": "TRACE-CAG load validation"},
        headers={"Authorization": "Bearer token-a"},
        name="chat:create-session",
        timeout=harness.REQUEST_TIMEOUT_SECONDS,
    )
    seed_call = client.post.call_args_list[1]
    assert seed_call.args == ("/api/v1/chat/messages",)
    assert seed_call.kwargs["json"] == {
        "user_id": "user-a",
        "session_id": "session-created",
        "message": f"Remember my private exercise code: {user.canary}",
    }
    assert seed_call.kwargs["headers"] == {"Authorization": "Bearer token-a"}
    assert seed_call.kwargs["name"] == "chat:seed"
    assert seed_call.kwargs["catch_response"] is True
    assert seed_call.kwargs["timeout"] == harness.REQUEST_TIMEOUT_SECONDS
    isolation_call = client.post.call_args_list[2]
    assert isolation_call.kwargs["json"]["session_id"] == "session-created"
    assert isolation_call.kwargs["json"]["message"] == (
        "What is my private exercise code? Reply with only the code."
    )
    assert isolation_call.kwargs["name"] == "chat:isolation"
    assert user.canary in harness._CANARIES


def test_repeated_topic_uses_shared_query_without_private_canary(monkeypatch):
    user = object.__new__(harness.TraceCAGLearnerUser)
    user.canary = "LXprivate"
    user._chat = MagicMock()
    monkeypatch.setattr(harness.random, "choice", lambda _items: "shared prompt")

    user.repeated_topic()

    user._chat.assert_called_once_with("shared prompt", "repeated")


def _chat_user_with_response(text: str):
    response = MagicMock(status_code=200, text=text)
    response.json.return_value = {"metadata": {}}
    context = MagicMock()
    context.__enter__.return_value = response
    user = object.__new__(harness.TraceCAGLearnerUser)
    user.user_id = "user-a"
    user.session_id = "session-a"
    user.token = "token-a"
    user.canary = "LXown"
    user.client = MagicMock()
    user.client.post.return_value = context
    return user, response


def test_isolation_response_with_own_canary_passes():
    user, response = _chat_user_with_response('{"response": "LXown"}')
    harness._CANARIES.add("LXown")

    user._chat("same isolation query", "isolation", require_own_canary=True)

    response.failure.assert_not_called()


def test_isolation_response_without_own_canary_fails():
    user, response = _chat_user_with_response('{"response": "unknown"}')
    harness._CANARIES.add("LXown")

    user._chat("same isolation query", "isolation", require_own_canary=True)

    response.failure.assert_called_once_with(
        "own learner canary missing from isolation response"
    )


def test_response_with_foreign_canary_fails():
    user, response = _chat_user_with_response('{"response": "LXforeign"}')
    harness._CANARIES.update({"LXown", "LXforeign"})

    user._chat("same isolation query", "isolation", require_own_canary=False)

    response.failure.assert_called_once_with(
        "cross-user canary leaked through personalized cache"
    )


def test_internal_state_leak_returns_false():
    user, response = _chat_user_with_response(
        '{"learner_concept_states": {"secret": true}}'
    )
    harness._CANARIES.add("LXown")

    result = user._chat("query", "repeated")

    assert result is False
    response.failure.assert_called_once_with("personalized internal state leaked")


def test_test_stop_fails_when_isolation_initialization_is_incomplete():
    harness._INITIALIZATIONS_STARTED = 2
    harness._INITIALIZATIONS_COMPLETED = 1
    stats = MagicMock()
    environment = SimpleNamespace(process_exit_code=0, runner=SimpleNamespace(stats=stats))

    harness.require_completed_isolation(environment)

    assert environment.process_exit_code == 1
    stats.log_error.assert_called_once()


def test_on_start_failed_isolation_remains_incomplete(monkeypatch):
    harness._IDENTITIES = [("token-a", "user-a")]
    session_response = MagicMock(status_code=201)
    session_response.json.return_value = {"session_id": "session-created"}
    user = object.__new__(harness.TraceCAGLearnerUser)
    user.client = MagicMock()
    user.client.post.return_value = session_response
    user.environment = SimpleNamespace(
        parsed_options=SimpleNamespace(token="", user_id="")
    )
    user._chat = MagicMock(side_effect=[True, False])
    monkeypatch.setattr(
        harness.uuid, "uuid4", lambda: SimpleNamespace(hex="abc123def4567890")
    )

    with pytest.raises(RuntimeError, match="isolation initialization failed"):
        user.on_start()

    assert harness._INITIALIZATIONS_STARTED == 1
    assert harness._INITIALIZATIONS_COMPLETED == 0
    assert user._chat.call_args_list[1] == call(
        "What is my private exercise code? Reply with only the code.",
        "isolation",
        require_own_canary=True,
    )


def test_chat_http_failure_returns_false_and_uses_request_timeout():
    user, response = _chat_user_with_response('{"detail": "timeout"}')
    response.status_code = 504

    result = user._chat("query", "isolation", require_own_canary=True)

    assert result is False
    response.failure.assert_called_once_with("HTTP 504")
    assert user.client.post.call_args.kwargs["timeout"] == (
        harness.REQUEST_TIMEOUT_SECONDS
    )


def test_test_stop_keeps_success_exit_code_when_all_initializations_complete():
    harness._INITIALIZATIONS_STARTED = 2
    harness._INITIALIZATIONS_COMPLETED = 2
    stats = MagicMock()
    environment = SimpleNamespace(process_exit_code=0, runner=SimpleNamespace(stats=stats))

    harness.require_completed_isolation(environment)

    assert environment.process_exit_code == 0
    stats.log_error.assert_not_called()
