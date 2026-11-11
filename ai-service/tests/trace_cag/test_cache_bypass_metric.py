"""A learner-state outage turns the cache off for every user, which shows up as LLM spend. It must be visible."""

import pytest

from api.services.telemetry import get_telemetry
from api.services.trace_cag import cache_utils

COUNTER = "tracecag_cache_bypass_learner_epoch_total"


@pytest.mark.asyncio
async def test_a_bypass_for_a_missing_learner_epoch_is_counted(monkeypatch):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")
    counters = get_telemetry().counters
    before = counters.get(COUNTER, 0)

    await cache_utils.cache_gate_node({
        "user_input": "Explain this",
        "user_id": "user-1",
        "learner_profile": {"level": "B1", "_learner_state_available": False},
        "cache_policy": "on",
    })

    assert counters[COUNTER] == before + 1


@pytest.mark.asyncio
async def test_a_turn_with_the_cache_switched_off_is_not_counted_as_a_bypass(monkeypatch):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")
    counters = get_telemetry().counters
    before = counters.get(COUNTER, 0)

    await cache_utils.cache_gate_node({
        "user_input": "Explain this",
        "user_id": "user-1",
        "learner_profile": {"level": "B1", "_learner_state_available": False},
        "cache_policy": "off",
    })

    assert counters.get(COUNTER, 0) == before
