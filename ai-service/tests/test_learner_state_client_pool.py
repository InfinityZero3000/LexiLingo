"""The learner-state client keeps as many idle connections as it allows in flight, so a busy turn does not pay a TCP handshake."""

from api.clients import learner_state_client
from api.clients.learner_state_client import LearnerStateClient


def _capture_limits(monkeypatch):
    seen = {}

    class FakeAsyncClient:
        def __init__(self, *, limits, timeout):
            seen["limits"] = limits

        async def aclose(self):
            return None

    monkeypatch.setattr(learner_state_client.httpx, "AsyncClient", FakeAsyncClient)
    return seen


def test_idle_connections_default_to_the_in_flight_limit(monkeypatch):
    seen = _capture_limits(monkeypatch)

    LearnerStateClient(token="t", max_inflight=60)

    assert seen["limits"].max_connections == 60
    assert seen["limits"].max_keepalive_connections == 60


def test_idle_connections_can_be_set_separately(monkeypatch):
    seen = _capture_limits(monkeypatch)

    LearnerStateClient(token="t", max_inflight=100, max_keepalive=30)

    assert seen["limits"].max_connections == 100
    assert seen["limits"].max_keepalive_connections == 30


def test_the_process_wide_client_reads_the_keepalive_setting(monkeypatch):
    seen = _capture_limits(monkeypatch)
    monkeypatch.setattr(learner_state_client, "_CLIENT", None)
    monkeypatch.setattr(learner_state_client.settings, "LEARNER_STATE_MAX_INFLIGHT", 80)
    monkeypatch.setattr(learner_state_client.settings, "LEARNER_STATE_MAX_KEEPALIVE", 25)

    learner_state_client.get_learner_state_client()

    assert seen["limits"].max_keepalive_connections == 25
    monkeypatch.setattr(learner_state_client, "_CLIENT", None)
