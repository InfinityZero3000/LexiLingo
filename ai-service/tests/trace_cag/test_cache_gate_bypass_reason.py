"""Every early exit of the cache gate names its reason in `cache_bypass` and logs it once."""

import logging
from unittest.mock import patch

import pytest

from api.services.trace_cag import cache_utils

LOGGER = "api.services.trace_cag.cache_utils"


def _bypass_logs(caplog):
    return [r.getMessage() for r in caplog.records if "cache bypass" in r.getMessage()]


@pytest.mark.asyncio
async def test_missing_learner_epoch_names_its_reason(monkeypatch, caplog):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "read")
    caplog.set_level(logging.INFO, logger=LOGGER)

    result = await cache_utils.cache_gate_node({
        "user_input": "Explain this", "user_id": "user-1",
        "learner_profile": {"level": "B1", "_learner_state_available": False}, "cache_policy": "on",
    })

    assert result["cache_bypass"] == "learner_epoch_unavailable"
    assert result["cache_decision"] == "full" and result["cache_hit"] is False
    assert len(_bypass_logs(caplog)) == 1 and "learner_epoch_unavailable" in _bypass_logs(caplog)[0]


@pytest.mark.asyncio
async def test_unresolvable_user_scope_names_its_reason(monkeypatch, caplog):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "off")
    caplog.set_level(logging.INFO, logger=LOGGER)

    with patch.object(cache_utils, "_user_cache_scope", autospec=True, return_value=None):
        result = await cache_utils.cache_gate_node({
            "user_input": "Explain this", "user_id": "user-1",
            "learner_profile": {"level": "B1"}, "cache_policy": "on",
        })

    assert result["cache_bypass"] == "user_cache_scope_unavailable"
    assert len(_bypass_logs(caplog)) == 1


@pytest.mark.asyncio
async def test_anonymous_request_names_its_reason(monkeypatch, caplog):
    monkeypatch.setattr(cache_utils.settings, "LEARNER_STATE_MODE", "off")
    caplog.set_level(logging.INFO, logger=LOGGER)

    result = await cache_utils.cache_gate_node({
        "user_input": "Explain this", "learner_profile": {"level": "B1"}, "cache_policy": "on",
    })

    assert result["cache_bypass"] == "no_user_cache_scope"
    assert len(_bypass_logs(caplog)) == 1


@pytest.mark.asyncio
async def test_policy_off_names_its_reason(caplog):
    caplog.set_level(logging.INFO, logger=LOGGER)

    result = await cache_utils.cache_gate_node({
        "user_input": "Explain this", "user_id": "user-1",
        "learner_profile": {"level": "B1"}, "cache_policy": "off",
    })

    assert result["cache_bypass"] == "cache_disabled"
    assert len(_bypass_logs(caplog)) == 1


def test_the_state_schema_carries_the_key():
    from api.services.trace_cag.state import TraceCAGState

    assert "cache_bypass" in TraceCAGState.__annotations__
