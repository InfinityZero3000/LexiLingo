import asyncio
import time
from unittest.mock import AsyncMock, MagicMock

import pytest
import httpx

from api.clients import learner_state_client
from api.clients.learner_state_client import LearnerStateClient


@pytest.mark.asyncio
async def test_batch_get_uses_one_request_and_returns_typed_state():
    response = MagicMock(status_code=200)
    response.json.return_value = {
        "state_epoch": 7,
        "states": [{"concept_id": "concept:a", "mastery_probability": 0.8}],
    }
    response.raise_for_status.return_value = None
    http = MagicMock()
    http.post = AsyncMock(return_value=response)
    client = LearnerStateClient(http_client=http, token="secret", audience="backend")

    result = await client.batch_get(
        "user-1", ["concept:a", "concept:a"], deadline=time.monotonic() + 0.1
    )

    assert result.degraded is False
    assert result.state_epoch == 7
    assert result.states["concept:a"]["mastery_probability"] == 0.8
    assert http.post.await_count == 1


@pytest.mark.asyncio
async def test_batch_get_parses_onboarding_goal_and_interest():
    response = MagicMock(status_code=200)
    response.json.return_value = {
        "state_epoch": 1,
        "states": [],
        "goal": "career",
        "interest": "technology",
    }
    response.raise_for_status.return_value = None
    http = MagicMock()
    http.post = AsyncMock(return_value=response)
    client = LearnerStateClient(http_client=http, token="secret", audience="backend")

    result = await client.batch_get("user-1", [], deadline=time.monotonic() + 0.1)

    assert result.goal == "career"
    assert result.interest == "technology"


@pytest.mark.asyncio
async def test_batch_get_defaults_goal_and_interest_when_absent():
    response = MagicMock(status_code=200)
    response.json.return_value = {"state_epoch": 1, "states": []}
    response.raise_for_status.return_value = None
    http = MagicMock()
    http.post = AsyncMock(return_value=response)
    client = LearnerStateClient(http_client=http, token="secret", audience="backend")

    result = await client.batch_get("user-1", [], deadline=time.monotonic() + 0.1)

    assert result.goal is None
    assert result.interest is None


@pytest.mark.asyncio
async def test_expired_deadline_degrades_without_http_request():
    http = MagicMock()
    http.post = AsyncMock()
    client = LearnerStateClient(http_client=http, token="secret", audience="backend")

    result = await client.batch_get("user-1", ["concept:a"], deadline=time.monotonic())

    assert result.degraded is True
    assert result.reason == "deadline_exceeded"
    http.post.assert_not_awaited()


@pytest.mark.asyncio
async def test_timeout_opens_circuit_and_subsequent_call_fast_fails():
    http = MagicMock()
    http.post = AsyncMock(side_effect=asyncio.TimeoutError)
    client = LearnerStateClient(
        http_client=http,
        token="secret",
        audience="backend",
        circuit_failures=1,
        circuit_reset_seconds=30,
    )

    first = await client.batch_get(
        "user-1", ["concept:a"], deadline=time.monotonic() + 0.1
    )
    second = await client.batch_get(
        "user-1", ["concept:a"], deadline=time.monotonic() + 0.1
    )

    assert first.reason == "timeout"
    assert second.reason == "circuit_open"
    assert http.post.await_count == 1


@pytest.mark.asyncio
async def test_bulkhead_wait_is_bounded_by_absolute_deadline():
    entered = asyncio.Event()
    release = asyncio.Event()

    async def blocked_post(*args, **kwargs):
        entered.set()
        await release.wait()
        return MagicMock(status_code=200, json=lambda: {"states": []})

    http = MagicMock()
    http.post = AsyncMock(side_effect=blocked_post)
    client = LearnerStateClient(
        http_client=http, token="secret", audience="backend", max_inflight=1
    )
    holder = asyncio.create_task(
        client.batch_get("user-1", ["a"], deadline=time.monotonic() + 1)
    )
    await entered.wait()

    waiting = await client.batch_get(
        "user-2", ["b"], deadline=time.monotonic() + 0.01
    )
    release.set()
    await holder

    assert waiting.degraded is True
    assert waiting.reason == "timeout"
    assert http.post.await_count == 1


@pytest.mark.asyncio
async def test_4xx_does_not_open_circuit_but_5xx_does():
    def failed_response(status_code: int) -> MagicMock:
        response = MagicMock(status_code=status_code)
        response.raise_for_status.side_effect = httpx.HTTPStatusError(
            "failed", request=MagicMock(), response=response
        )
        return response

    http = MagicMock()
    http.post = AsyncMock(
        side_effect=[failed_response(404), failed_response(503)]
        + [failed_response(503)]
    )
    client = LearnerStateClient(
        http_client=http,
        token="secret",
        audience="backend",
        circuit_failures=1,
        circuit_reset_seconds=30,
    )

    not_found = await client.batch_get(
        "user-1", ["a"], deadline=time.monotonic() + 0.1
    )
    unavailable = await client.batch_get(
        "user-1", ["a"], deadline=time.monotonic() + 0.1
    )
    fast_fail = await client.batch_get(
        "user-1", ["a"], deadline=time.monotonic() + 0.1
    )

    assert not_found.reason == "http_404"
    assert unavailable.reason == "http_503"
    assert fast_fail.reason == "circuit_open"
    assert http.post.await_count == 3  # 404 once, then one safe retry for 503


@pytest.mark.asyncio
async def test_cancellation_propagates_and_does_not_trip_circuit():
    started = asyncio.Event()

    async def cancellable_post(*args, **kwargs):
        started.set()
        await asyncio.Event().wait()

    http = MagicMock()
    http.post = AsyncMock(side_effect=cancellable_post)
    client = LearnerStateClient(
        http_client=http, token="secret", audience="backend", circuit_failures=1
    )
    task = asyncio.create_task(
        client.batch_get("user-1", ["a"], deadline=time.monotonic() + 1)
    )
    await started.wait()
    task.cancel()

    with pytest.raises(asyncio.CancelledError):
        await task

    assert client._failure_count == 0
    assert client._circuit_open_until == 0


@pytest.mark.asyncio
async def test_close_does_not_close_injected_http_client():
    http = MagicMock()
    http.aclose = AsyncMock()
    client = LearnerStateClient(http_client=http, token="secret", audience="backend")

    await client.close()

    http.aclose.assert_not_awaited()


@pytest.mark.asyncio
async def test_close_closes_owned_http_client(monkeypatch):
    http = MagicMock()
    http.aclose = AsyncMock()
    monkeypatch.setattr(httpx, "AsyncClient", MagicMock(return_value=http))
    client = LearnerStateClient(token="secret", audience="backend")

    await client.close()

    http.aclose.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_process_client_shutdown_closes_and_resets_singleton(monkeypatch):
    client = MagicMock()
    client.close = AsyncMock()
    monkeypatch.setattr(learner_state_client, "_CLIENT", client)

    await learner_state_client.close_learner_state_client()

    client.close.assert_awaited_once_with()
    assert learner_state_client._CLIENT is None

    # Shutdown hooks may run defensively more than once.
    await learner_state_client.close_learner_state_client()
    client.close.assert_awaited_once_with()


@pytest.mark.asyncio
async def test_send_observations_preserves_event_id_and_accepts_duplicate_ack():
    event_id = "a" * 64
    response = MagicMock(status_code=200)
    response.json.return_value = {
        "accepted_event_ids": [],
        "duplicate_event_ids": [event_id],
    }
    http = MagicMock()
    http.post = AsyncMock(return_value=response)
    client = LearnerStateClient(http_client=http, token="secret", audience="backend")

    result = await client.send_observations([{"event_id": event_id}], timeout_seconds=1)

    assert result["duplicate_event_ids"] == [event_id]
    request = http.post.await_args
    assert request.args[0].endswith("/learner-state/observations:batch")
    assert request.kwargs["json"]["observations"][0]["event_id"] == event_id
