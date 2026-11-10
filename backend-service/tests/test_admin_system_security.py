from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException

from app.routes import admin_system


@pytest.mark.asyncio
async def test_seed_is_hidden_outside_development(monkeypatch):
    monkeypatch.setattr(admin_system.settings, "APP_ENV", "production")

    with pytest.raises(HTTPException) as exc_info:
        await admin_system.seed_sample_data(db=MagicMock(), admin_user=MagicMock())

    assert exc_info.value.status_code == 404
