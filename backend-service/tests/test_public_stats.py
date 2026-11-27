"""The public counter advertises real learners only, and only once there are enough."""

from datetime import datetime, timezone

from app.core.config import settings
from app.models.progress import DailyActivity
from app.models.user import User


def _user(email: str) -> User:
    return User(email=email, username=email.split("@")[0], hashed_password="x", display_name="n", is_active=True)


async def test_counts_real_learners_and_hides_a_small_number(async_client, db_session, monkeypatch):
    monkeypatch.setattr(settings, "PUBLIC_STATS_MIN_LEARNERS", 1000)
    real, seed = _user("real@example.com"), _user("fake@lexilingo.test")
    db_session.add_all([real, seed])
    await db_session.flush()
    today = datetime.now(timezone.utc).date()
    db_session.add_all([
        DailyActivity(user_id=real.id, activity_date=today, lessons_completed=3),
        DailyActivity(user_id=seed.id, activity_date=today, lessons_completed=50),
    ])
    await db_session.commit()

    body = (await async_client.get("/api/v1/public/stats")).json()

    assert body == {"learners": 1, "lessons_completed_today": 3, "show": False}


async def test_show_turns_on_at_the_floor(async_client, db_session, monkeypatch):
    monkeypatch.setattr(settings, "PUBLIC_STATS_MIN_LEARNERS", 2)
    db_session.add_all([_user("a@example.com"), _user("b@example.com")])
    await db_session.commit()

    assert (await async_client.get("/api/v1/public/stats")).json()["show"] is True


async def test_answer_is_cached(async_client, db_session, monkeypatch):
    store: dict = {}

    async def fake_get(key):
        return store.get(key)

    async def fake_set(key, value, ttl=60):
        store[key] = value

    monkeypatch.setattr("app.routes.public_stats.get_cached", fake_get)
    monkeypatch.setattr("app.routes.public_stats.set_cached", fake_set)
    first = (await async_client.get("/api/v1/public/stats")).json()
    db_session.add(_user("late@example.com"))
    await db_session.commit()

    assert (await async_client.get("/api/v1/public/stats")).json() == first
