from datetime import UTC, datetime

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.product_event import ProductEvent
from app.models.user import User

BASE = "/api/v1/analytics/events"


@pytest.mark.asyncio
async def test_ingests_authenticated_event_batch(
    async_client: AsyncClient,
    db_session: AsyncSession,
    test_user: User,
    auth_headers: dict[str, str],
) -> None:
    payload = {
        "events": [
            {
                "event_id": "11111111-1111-4111-8111-111111111111",
                "event_name": "session_summary_shown",
                "source": "topic_chat",
                "properties": {"mistakes_saved": 2},
                "client_timestamp": "2026-08-11T01:02:03Z",
            },
            {
                "event_id": "22222222-2222-4222-8222-222222222222",
                "event_name": "task_tapped",
                "source": "today_plan",
                "properties": {"task_type": "vocabulary_review"},
                "client_timestamp": "2026-08-11T01:02:04+00:00",
            },
        ]
    }
    response = await async_client.post(
        BASE,
        headers=auth_headers,
        json=payload,
    )
    duplicate_response = await async_client.post(BASE, headers=auth_headers, json=payload)

    assert response.status_code == 202
    assert response.json() == {"accepted": 2}
    assert duplicate_response.status_code == 202

    result = await db_session.execute(select(ProductEvent).order_by(ProductEvent.client_timestamp))
    events = result.scalars().all()
    assert [event.event_name for event in events] == [
        "session_summary_shown",
        "task_tapped",
    ]
    assert all(event.user_id == test_user.id for event in events)
    assert events[0].source == "topic_chat"
    assert events[0].properties == {"mistakes_saved": 2}
    assert events[0].client_timestamp == datetime(2026, 8, 11, 1, 2, 3, tzinfo=UTC)
    assert all(event.created_at.tzinfo is not None for event in events)


@pytest.mark.asyncio
async def test_content_interaction_is_ingested_and_bumps_interaction_epoch(
    async_client: AsyncClient,
    db_session: AsyncSession,
    test_user: User,
    auth_headers: dict[str, str],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.core.redis import RedisClient
    from app.services.recommendation_service import _get_interaction_epoch

    class FakeRedis:
        def __init__(self):
            self.store: dict[str, int] = {}

        async def get(self, key):
            return self.store.get(key)

        async def incr(self, key):
            self.store[key] = self.store.get(key, 0) + 1
            return self.store[key]

    fake = FakeRedis()

    async def fake_get_instance():
        return fake

    monkeypatch.setattr(RedisClient, "get_instance", fake_get_instance)

    before = await _get_interaction_epoch(test_user.id)

    response = await async_client.post(
        BASE,
        headers=auth_headers,
        json={
            "events": [
                {
                    "event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    "event_name": "content_interaction",
                    "source": "app",
                    "properties": {
                        "item_type": "course",
                        "item_id": "c1",
                        "action": "open",
                        "topic": "travel",
                        "dwell_ms": 1200,
                    },
                    "client_timestamp": "2026-08-11T01:02:03Z",
                }
            ]
        },
    )

    assert response.status_code == 202
    result = await db_session.execute(select(ProductEvent))
    events = result.scalars().all()
    assert events[0].properties["topic"] == "travel"
    assert await _get_interaction_epoch(test_user.id) == before + 1

    # Resending the exact same event_id is a pure conflict — nothing new was
    # written, so the epoch must not bump again.
    replay = await async_client.post(BASE, headers=auth_headers, json={
        "events": [
            {
                "event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                "event_name": "content_interaction",
                "source": "app",
                "properties": {
                    "item_type": "course",
                    "item_id": "c1",
                    "action": "open",
                    "topic": "travel",
                    "dwell_ms": 1200,
                },
                "client_timestamp": "2026-08-11T01:02:03Z",
            }
        ]
    })

    assert replay.status_code == 202
    assert await _get_interaction_epoch(test_user.id) == before + 1


@pytest.mark.asyncio
async def test_ingestion_requires_authentication(async_client: AsyncClient) -> None:
    response = await async_client.post(
        BASE,
        json={
            "events": [
                {
                    "event_id": "33333333-3333-4333-8333-333333333333",
                    "event_name": "card_tapped",
                    "source": "today_plan",
                    "client_timestamp": "2026-08-11T01:02:03Z",
                }
            ]
        },
    )

    assert response.status_code == 401


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "events",
    [
        [],
        [
            {
                "event_id": "44444444-4444-4444-8444-444444444444",
                "event_name": "Invalid Event Name",
                "source": "topic_chat",
                "client_timestamp": "2026-08-11T01:02:03Z",
            }
        ],
        [
            {
                "event_id": "55555555-5555-4555-8555-555555555555",
                "event_name": "session_summary_shown",
                "source": "topic_chat",
                "client_timestamp": "2026-08-11T01:02:03",
            }
        ],
        [
            {
                "event_id": "66666666-6666-4666-8666-666666666666",
                "event_name": "session_summary_shown",
                "source": "topic_chat",
                "properties": {"email": "learner@example.com"},
                "client_timestamp": "2026-08-11T01:02:03Z",
            }
        ],
        [
            {
                "event_id": "77777777-7777-4777-8777-777777777777",
                "event_name": "session_summary_shown",
                "source": "topic_chat",
                "properties": {"level": {"raw": "nested"}},
                "client_timestamp": "2026-08-11T01:02:03Z",
            }
        ],
        [
            {
                "event_id": "88888888-8888-4888-8888-888888888888",
                "event_name": "session_summary_shown",
                "source": "topic_chat",
                "properties": {"level": "x" * 101},
                "client_timestamp": "2026-08-11T01:02:03Z",
            }
        ],
    ],
)
async def test_rejects_invalid_batches(
    async_client: AsyncClient,
    auth_headers: dict[str, str],
    events: list[dict[str, object]],
) -> None:
    response = await async_client.post(BASE, headers=auth_headers, json={"events": events})

    assert response.status_code == 422


@pytest.mark.asyncio
async def test_rejects_non_finite_property(
    async_client: AsyncClient,
    auth_headers: dict[str, str],
) -> None:
    response = await async_client.post(
        BASE,
        headers={**auth_headers, "content-type": "application/json"},
        content=b'{"events":[{"event_id":"99999999-9999-4999-8999-999999999999",'
        b'"event_name":"pronunciation_score_shown","source":"lexi_chat",'
        b'"properties":{"score":NaN},"client_timestamp":"2026-08-11T01:02:03Z"}]}',
    )

    assert response.status_code == 422
