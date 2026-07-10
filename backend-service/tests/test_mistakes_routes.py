"""Tests for synced mistake notebook API routes."""

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import create_access_token
from app.models.user import User


def _payload(**overrides):
    data = {
        "id": "mistake_news_001",
        "source_type": "news_quiz",
        "source_id": "article_123",
        "source_title": "Solar Panels Power Local School",
        "question": "What is the main idea of the article?",
        "selected_answer": "The school cancelled the project",
        "correct_answer": "The school installed solar panels",
        "explanation": "The article focuses on a renewable energy project.",
        "skill": "reading",
        "metadata": {"question_id": "q1"},
    }
    data.update(overrides)
    return data


@pytest.mark.asyncio
async def test_mistakes_require_authentication(async_client):
    response = await async_client.get("/api/v1/mistakes")

    assert response.status_code in {401, 403}


@pytest.mark.asyncio
async def test_create_and_list_mistake(async_client, auth_headers):
    response = await async_client.post(
        "/api/v1/mistakes",
        headers=auth_headers,
        json=_payload(),
    )

    assert response.status_code == 201
    created = response.json()["data"]
    assert created["id"] == "mistake_news_001"
    assert created["status"] == "open"
    assert created["attempt_count"] == 1
    assert created["metadata"] == {"question_id": "q1"}

    list_response = await async_client.get("/api/v1/mistakes", headers=auth_headers)

    assert list_response.status_code == 200
    entries = list_response.json()["data"]
    assert len(entries) == 1
    assert entries[0]["id"] == "mistake_news_001"


@pytest.mark.asyncio
async def test_duplicate_mistake_refreshes_existing_entry(async_client, auth_headers):
    await async_client.post("/api/v1/mistakes", headers=auth_headers, json=_payload())
    reviewed = await async_client.patch(
        "/api/v1/mistakes/mistake_news_001/review",
        headers=auth_headers,
    )
    assert reviewed.status_code == 200
    assert reviewed.json()["data"]["status"] == "reviewed"

    duplicate = await async_client.post(
        "/api/v1/mistakes",
        headers=auth_headers,
        json=_payload(explanation="A refreshed explanation."),
    )

    assert duplicate.status_code == 201
    data = duplicate.json()["data"]
    assert data["id"] == "mistake_news_001"
    assert data["status"] == "open"
    assert data["reviewed_at"] is None
    assert data["review_count"] == 1
    assert data["attempt_count"] == 2
    assert data["explanation"] == "A refreshed explanation."

    list_response = await async_client.get("/api/v1/mistakes?status=all", headers=auth_headers)
    assert len(list_response.json()["data"]) == 1


@pytest.mark.asyncio
async def test_duplicate_without_client_id_uses_source_question_fallback(
    async_client,
    auth_headers,
):
    payload = _payload()
    payload.pop("id")

    first = await async_client.post(
        "/api/v1/mistakes",
        headers=auth_headers,
        json=payload,
    )
    assert first.status_code == 201
    server_id = first.json()["data"]["id"]
    assert server_id.startswith("mistake_") is False

    duplicate = await async_client.post(
        "/api/v1/mistakes",
        headers=auth_headers,
        json=_payload(
            id=None,
            selected_answer="Different wrong answer",
            explanation="Fallback duplicate.",
        ),
    )
    assert duplicate.status_code == 201
    data = duplicate.json()["data"]
    assert data["id"] == server_id
    assert data["attempt_count"] == 2
    assert data["selected_answer"] == "Different wrong answer"
    assert data["explanation"] == "Fallback duplicate."

    reviewed = await async_client.patch(
        f"/api/v1/mistakes/{server_id}/review",
        headers=auth_headers,
    )
    assert reviewed.status_code == 200
    assert reviewed.json()["data"]["status"] == "reviewed"

    deleted = await async_client.delete(
        f"/api/v1/mistakes/{server_id}",
        headers=auth_headers,
    )
    assert deleted.status_code == 200


@pytest.mark.asyncio
async def test_create_ignores_client_owned_review_state(async_client, auth_headers):
    response = await async_client.post(
        "/api/v1/mistakes",
        headers=auth_headers,
        json=_payload(
            reviewed_at="2099-01-01T00:00:00Z",
            review_count=999999,
            created_at="2099-01-01T00:00:00Z",
        ),
    )

    assert response.status_code == 201
    data = response.json()["data"]
    assert data["status"] == "open"
    assert data["reviewed_at"] is None
    assert data["review_count"] == 0
    assert not data["created_at"].startswith("2099")


@pytest.mark.asyncio
async def test_review_reopen_and_delete_mistake(async_client, auth_headers):
    await async_client.post("/api/v1/mistakes", headers=auth_headers, json=_payload())

    reviewed = await async_client.patch(
        "/api/v1/mistakes/mistake_news_001/review",
        headers=auth_headers,
    )
    assert reviewed.status_code == 200
    assert reviewed.json()["data"]["status"] == "reviewed"
    assert reviewed.json()["data"]["review_count"] == 1

    open_list = await async_client.get("/api/v1/mistakes", headers=auth_headers)
    assert open_list.json()["data"] == []

    reviewed_list = await async_client.get(
        "/api/v1/mistakes?status=reviewed",
        headers=auth_headers,
    )
    assert len(reviewed_list.json()["data"]) == 1

    reopened = await async_client.patch(
        "/api/v1/mistakes/mistake_news_001/reopen",
        headers=auth_headers,
    )
    assert reopened.status_code == 200
    assert reopened.json()["data"]["status"] == "open"
    assert reopened.json()["data"]["reviewed_at"] is None

    deleted = await async_client.delete(
        "/api/v1/mistakes/mistake_news_001",
        headers=auth_headers,
    )
    assert deleted.status_code == 200
    assert deleted.json()["message"] == "Mistake deleted"

    list_response = await async_client.get("/api/v1/mistakes?status=all", headers=auth_headers)
    assert list_response.json()["data"] == []


@pytest.mark.asyncio
async def test_mistakes_are_user_isolated(
    async_client,
    auth_headers,
    db_session: AsyncSession,
):
    await async_client.post("/api/v1/mistakes", headers=auth_headers, json=_payload())

    other_user = User(
        email="other@example.com",
        username="otheruser",
        hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
        display_name="Other User",
        is_active=True,
        is_verified=True,
        native_language="vi",
        target_language="en",
        level="beginner",
    )
    db_session.add(other_user)
    await db_session.commit()
    await db_session.refresh(other_user)
    other_headers = {
        "Authorization": f"Bearer {create_access_token(data={'sub': str(other_user.id)})}"
    }

    other_list = await async_client.get(
        "/api/v1/mistakes?status=all",
        headers=other_headers,
    )
    assert other_list.status_code == 200
    assert other_list.json()["data"] == []

    other_review = await async_client.patch(
        "/api/v1/mistakes/mistake_news_001/review",
        headers=other_headers,
    )
    assert other_review.status_code == 404
