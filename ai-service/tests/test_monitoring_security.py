"""Unit tests to verify security of AI Service monitoring and telemetry routes."""

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from httpx import AsyncClient, ASGITransport
from unittest.mock import AsyncMock, MagicMock, patch

from api.routes.ai import router


def _make_app() -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    return app


@pytest.mark.asyncio
async def test_monitoring_dashboard_no_auth_header_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    app = _make_app()
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/monitoring/dashboard")
        
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_monitoring_dashboard_correct_auth_header_passes(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    app = _make_app()
    
    # Mock telemetry, performance monitor, and trace cag dependencies
    telemetry_mock = MagicMock()
    telemetry_mock.get_dashboard_data.return_value = {"status": "ok"}
    telemetry_mock.check_performance_targets.return_value = []
    
    perf_mock = MagicMock()
    perf_mock.get_system_stats.return_value = {}
    perf_mock.check_resource_health.return_value = {"healthy": True}
    perf_mock.get_process_stats.return_value = {}
    
    # Patch where the objects are defined as they are locally imported in the router function
    with patch("api.services.telemetry.get_telemetry", return_value=telemetry_mock), \
         patch("api.services.performance_monitor.get_performance_monitor", return_value=perf_mock), \
         patch("api.routes.ai.get_trace_cag", return_value=AsyncMock()):
         
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
            response = await client.get("/monitoring/dashboard", headers={"X-Admin-Key": "test-admin-key"})
            
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_monitoring_metrics_no_auth_header_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    app = _make_app()
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/monitoring/metrics/some-metric")
        
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_monitoring_system_no_auth_header_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    app = _make_app()
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/monitoring/system")
        
    assert response.status_code == 403


@pytest.mark.asyncio
async def test_monitoring_health_no_auth_header_returns_403(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "test-admin-key")
    app = _make_app()
    
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
        response = await client.get("/monitoring/health")
        
    assert response.status_code == 403
