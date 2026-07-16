from unittest.mock import AsyncMock

import pytest

from api.services import kg_service_v3


@pytest.mark.asyncio
async def test_mastery_mutation_is_skipped_when_flag_is_disabled(monkeypatch):
    service = object.__new__(kg_service_v3.KnowledgeGraphServiceV3)
    service._execute = AsyncMock()
    monkeypatch.setattr(
        kg_service_v3.settings, "KUZU_USER_MASTERY_WRITES_ENABLED", False
    )

    await service.record_interaction(
        "user-1", "session-1", ["concept:a"], ["past_tense"]
    )

    service._execute.assert_not_awaited()


@pytest.mark.asyncio
async def test_mastery_mutation_invalidates_user_dependency(monkeypatch):
    service = object.__new__(kg_service_v3.KnowledgeGraphServiceV3)
    service._execute = AsyncMock()
    invalidate = AsyncMock(return_value={"artifact-1"})
    monkeypatch.setattr(
        kg_service_v3.settings, "KUZU_USER_MASTERY_WRITES_ENABLED", True
    )
    monkeypatch.setattr(
        "api.services.trace_cag.cache_utils.invalidate_dependency", invalidate
    )

    await service.record_interaction(
        "user-1", "session-1", ["concept:a"], ["past_tense"]
    )

    invalidate.assert_awaited_once()
    assert invalidate.await_args.args[0] == "learner:user-1:profile"
    assert invalidate.await_args.args[1].startswith("mastery:")
