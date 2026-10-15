from pathlib import Path
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from fastapi.routing import APIRoute

from app.core.dependencies import get_current_super_admin
from app.routes import admin_system


@pytest.mark.asyncio
async def test_seed_is_hidden_outside_development(monkeypatch):
    monkeypatch.setattr(admin_system.settings, "APP_ENV", "production")

    with pytest.raises(HTTPException) as exc_info:
        await admin_system.seed_sample_data(db=MagicMock(), admin_user=MagicMock())

    assert exc_info.value.status_code == 404


def test_system_info_update_excludes_ai_service_url():
    assert "ai_service_url" not in admin_system.SystemInfoUpdate.model_fields


def test_system_info_update_requires_super_admin():
    route = next(
        route
        for route in admin_system.router.routes
        if isinstance(route, APIRoute)
        and route.path == "/admin/system-info"
        and "PUT" in route.methods
    )
    assert get_current_super_admin in {
        dependency.call for dependency in route.dependant.dependencies
    }


@pytest.mark.asyncio
async def test_system_info_update_keeps_ai_url_immutable(monkeypatch):
    write_text = MagicMock()
    monkeypatch.setattr(Path, "write_text", write_text)
    monkeypatch.setattr(admin_system.settings, "APP_NAME", "before")
    monkeypatch.setattr(admin_system.settings, "AI_SERVICE_URL", "https://trusted.example")
    payload = admin_system.SystemInfoUpdate.model_validate(
        {
            "app_name": "after",
            "ai_service_url": "http://attacker.example",
        }
    )

    await admin_system.update_system_info(payload, admin_user=MagicMock())

    assert admin_system.settings.APP_NAME == "after"
    assert admin_system.settings.AI_SERVICE_URL == "https://trusted.example"
    write_text.assert_not_called()
