"""Topic affinity: the signal the recommender reads a learner's interests from."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.product_event import ProductEvent
from app.models.user import User
from app.services.recommendation_service import build_topic_affinity

pytestmark = pytest.mark.asyncio


async def _event(
    db: AsyncSession,
    user: User,
    topic: str,
    action: str,
    *,
    days_ago: float = 0.0,
    name: str = "content_interaction",
) -> None:
    created = datetime.now(UTC) - timedelta(days=days_ago)
    db.add(
        ProductEvent(
            event_id=uuid.uuid4(),
            user_id=user.id,
            event_name=name,
            source="test",
            properties={"item_type": "course", "item_id": "x", "action": action, "topic": topic},
            client_timestamp=created,
            created_at=created,
        )
    )
    await db.flush()


async def test_most_picked_topic_wins(db_session: AsyncSession, test_user: User):
    for _ in range(3):
        await _event(db_session, test_user, "travel", "complete")
    await _event(db_session, test_user, "business", "open")

    affinity = await build_topic_affinity(db_session, test_user.id)

    assert affinity["travel"] == 1.0  # normalized to the peak
    assert affinity["business"] < affinity["travel"]


async def test_recent_interest_outweighs_old(db_session: AsyncSession, test_user: User):
    # Same action, same count — only age differs.
    for _ in range(2):
        await _event(db_session, test_user, "music", "complete", days_ago=45)
        await _event(db_session, test_user, "cooking", "complete", days_ago=1)

    affinity = await build_topic_affinity(db_session, test_user.id)

    assert affinity["cooking"] > affinity["music"]


async def test_skips_do_not_earn_affinity(db_session: AsyncSession, test_user: User):
    await _event(db_session, test_user, "sports", "skip")
    await _event(db_session, test_user, "travel", "complete")

    affinity = await build_topic_affinity(db_session, test_user.id)

    # A negative signal must drop out entirely, never rank as mild interest.
    assert "sports" not in affinity
    assert affinity["travel"] == 1.0


async def test_ignores_other_event_names(db_session: AsyncSession, test_user: User):
    await _event(db_session, test_user, "travel", "open", name="srs_reminder_shown")

    assert await build_topic_affinity(db_session, test_user.id) == {}


async def test_endpoint_degrades_instead_of_failing(
    async_client, auth_headers: dict, monkeypatch
):
    """ai-service being unreachable must not take Home's rail down with it."""
    monkeypatch.delenv("AI_ADMIN_API_KEY", raising=False)

    response = await async_client.get(
        "/api/v1/recommendations?surface=home&limit=5", headers=auth_headers
    )

    assert response.status_code == 200
    body = response.json()["data"]
    assert body["degraded"] is True
    assert body["surface"] == "home"
    assert isinstance(body["items"], list)
