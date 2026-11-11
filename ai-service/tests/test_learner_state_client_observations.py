"""send_observations must encode what the spool really holds: Mongo hands back naive UTC datetimes, and the backend refuses an observed_at with no offset."""

import json
from datetime import UTC, datetime

import httpx
import pytest

from api.clients.learner_state_client import LearnerStateClient


def _client(handler):
    http = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    return LearnerStateClient(token="t", http_client=http)


@pytest.mark.asyncio
@pytest.mark.parametrize("stamp", [datetime(2026, 8, 12, 10, 35, 34), datetime(2026, 8, 12, 10, 35, 34, tzinfo=UTC)], ids=["naive-as-mongo-returns", "aware"])
async def test_observed_at_is_sent_as_an_aware_iso_string_and_acknowledged(stamp):
    seen = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["body"] = json.loads(request.content)
        seen["type"] = request.headers["content-type"]
        return httpx.Response(200, json={"accepted_event_ids": ["e1"], "duplicate_event_ids": []})

    result = await _client(handler).send_observations(
        [{"event_id": "e1", "concept_id": "concept:grammar.modal_can_could", "outcome": "incorrect", "confidence": 0.8, "observed_at": stamp, "payload": {"error_count": 2}}]
    )

    assert result["accepted_event_ids"] == ["e1"]
    assert seen["type"] == "application/json"
    sent = datetime.fromisoformat(seen["body"]["observations"][0]["observed_at"])
    assert sent.utcoffset() is not None
    assert sent == datetime(2026, 8, 12, 10, 35, 34, tzinfo=UTC)
