"""Tests for the internal error-diagnosis endpoint."""

from unittest.mock import AsyncMock, patch

import pytest
from fastapi import FastAPI
from httpx import ASGITransport, AsyncClient

from api.routes.error_diagnosis import router


def _make_app() -> FastAPI:
    app = FastAPI()
    app.include_router(router)
    return app


@pytest.mark.asyncio
async def test_diagnose_requires_admin_key(monkeypatch):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "secret-key")

    async with AsyncClient(
        transport=ASGITransport(app=_make_app()), base_url="http://test"
    ) as client:
        response = await client.post(
            "/api/v1/internal/diagnose",
            json={"text": "I goes home", "level": "A2"},
        )

    assert response.status_code == 403


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("level", "expected_level"),
    [("A2", "A2"), (None, "B1")],
)
async def test_diagnose_returns_mapped_result(monkeypatch, level, expected_level):
    monkeypatch.setenv("AI_ADMIN_API_KEY", "valid-admin-key")
    diagnosis = {
        "diagnosis_errors": [
            {
                "span": "I goes",
                "type": "subject_verb_agreement",
                "correction": "I go",
                "explanation": "Use go with I.",
            }
        ],
        "diagnosis_intent": "correct",
        "diagnosis_confidence": 0.95,
    }

    with patch(
        "api.routes.error_diagnosis.diagnose_node",
        new=AsyncMock(return_value=diagnosis),
    ) as diagnose_mock:
        async with AsyncClient(
            transport=ASGITransport(app=_make_app()), base_url="http://test"
        ) as client:
            response = await client.post(
                "/api/v1/internal/diagnose",
                json={"text": "I goes home", "level": level},
                headers={"X-Admin-Api-Key": "valid-admin-key"},
            )

    assert response.status_code == 200
    assert response.json() == {
        "errors": diagnosis["diagnosis_errors"],
        "intent": "correct",
        "confidence": 0.95,
    }
    diagnose_mock.assert_awaited_once_with(
        {"user_input": "I goes home", "learner_profile": {"level": expected_level}}
    )
