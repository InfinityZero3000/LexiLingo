"""The server-side premium boundary.

The Flutter client also gates premium UI, but from the local RevenueCat SDK,
which a patched build controls. `require_premium` is what actually decides.
"""

import uuid
from unittest.mock import AsyncMock, patch

import pytest
from fastapi import HTTPException

from app.core.dependencies import require_premium


class _User:
    def __init__(self):
        self.id = uuid.uuid4()


@pytest.mark.asyncio
async def test_active_entitlement_passes_the_user_through():
    user = _User()
    with patch(
        "app.services.entitlement_service.EntitlementService.is_active",
        new=AsyncMock(return_value=True),
    ):
        assert await require_premium(current_user=user, db=AsyncMock()) is user


@pytest.mark.asyncio
async def test_missing_entitlement_is_rejected_with_402():
    with patch(
        "app.services.entitlement_service.EntitlementService.is_active",
        new=AsyncMock(return_value=False),
    ):
        with pytest.raises(HTTPException) as exc:
            await require_premium(current_user=_User(), db=AsyncMock())
    assert exc.value.status_code == 402


@pytest.mark.asyncio
async def test_decision_reads_the_server_row_for_this_user():
    """It must never take an entitlement the caller supplied."""
    user = _User()
    is_active = AsyncMock(return_value=True)
    with patch(
        "app.services.entitlement_service.EntitlementService.is_active", new=is_active
    ):
        await require_premium(current_user=user, db=AsyncMock())
    assert is_active.await_args.args[1] == user.id
