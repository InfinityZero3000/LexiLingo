from datetime import datetime, timedelta, timezone

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.database import get_db
from app.core.security import create_access_token, get_password_hash
from app.main import app
from app.models.progress import DailyActivity, LessonCompletion, UserCourseProgress, UserProgress
from app.models.rbac import Role
from app.models.user import User

URL = "/api/v1/admin/analytics/dashboard/activation-funnel"


@pytest.fixture
async def admin_headers(db_session):
    from tests.conftest import seed_admin_permissions

    role = Role(name="Admin", slug="admin", level=1, description="Admin", is_system=True, is_active=True)
    db_session.add(role)
    await db_session.commit()
    await seed_admin_permissions(db_session)
    admin = User(
        email="funnel_admin@corp.com", username="funneladmin", hashed_password=get_password_hash("x" * 12),
        is_active=True, is_verified=True, role_id=role.id, created_at=datetime.now(timezone.utc) - timedelta(days=400),
    )
    db_session.add(admin)
    await db_session.commit()
    await db_session.refresh(admin)

    async def override():
        yield db_session

    app.dependency_overrides[get_db] = override
    yield {"Authorization": f"Bearer {create_access_token(data={'sub': str(admin.id)})}"}
    app.dependency_overrides.pop(get_db, None)


def make_user(name: str, days_ago: int, *, domain: str = "gmail.com", **kw) -> User:
    return User(
        email=f"{name}@{domain}", username=name, hashed_password="x",
        created_at=datetime.now(timezone.utc) - timedelta(days=days_ago), **kw,
    )


async def get(headers, days: int = 90) -> dict:
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        r = await c.get(f"{URL}?days={days}", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


def step(body: dict, key: str) -> dict:
    return next(s for s in body["steps"] if s["key"] == key)


@pytest.mark.asyncio
async def test_requires_admin(db_session):
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        assert (await c.get(URL)).status_code == 401


@pytest.mark.asyncio
async def test_funnel_counts_each_step_and_excludes_seed_accounts(db_session, admin_headers, test_lesson, test_course):
    unverified = make_user("unverified", 10)
    emailed = make_user("emailed", 10, is_verified=True, provider=["local"])
    googler = make_user("googler", 10, is_verified=True, provider=["google"], is_onboarding_completed=True)
    learner = make_user("learner", 10, is_verified=True, provider=["google"], is_onboarding_completed=True)
    finisher = make_user("finisher", 10, is_verified=True, provider=["local", "google"], is_onboarding_completed=True)
    old = make_user("old", 200, is_verified=True)
    seeds = [
        make_user("demo_1", 10, domain="lexilingo.dev", is_verified=True),
        make_user("seed_1", 10, domain="lexilingo.test", is_verified=True, is_onboarding_completed=True),
    ]
    db_session.add_all([unverified, emailed, googler, learner, finisher, old, *seeds])
    await db_session.commit()

    lid, cid = test_lesson.id, test_course.id
    db_session.add_all([
        UserCourseProgress(user_id=learner.id, course_id=cid),
        UserCourseProgress(user_id=finisher.id, course_id=cid),
        UserCourseProgress(user_id=seeds[1].id, course_id=cid),
        UserProgress(user_id=learner.id, lesson_id=lid, course_id=cid, status="in_progress"),
        UserProgress(user_id=finisher.id, lesson_id=lid, course_id=cid, status="not_started"),
        LessonCompletion(user_id=finisher.id, lesson_id=lid, is_passed=True),
    ])
    await db_session.commit()

    body = await get(admin_headers)
    counts = {s["key"]: s["count"] for s in body["steps"]}
    assert counts == {
        "signed_up": 5,
        "email_verified": 4,
        "onboarding_completed": 3,
        "enrolled": 2,
        "lesson_started": 1,
        "lesson_completed": 1,
    }
    verified = step(body, "email_verified")
    assert verified["breakdown"] == {"with_google_provider": 3, "without_google_provider": 1}
    assert step(body, "lesson_started")["pct_of_first"] == 20.0
    assert step(body, "lesson_completed")["pct_of_previous"] == 100.0
    assert step(body, "signed_up")["pct_of_previous"] is None
    assert all(s["definition"] for s in body["steps"])


@pytest.mark.asyncio
async def test_window_excludes_older_signups(db_session, admin_headers):
    db_session.add_all([make_user("recent", 3), make_user("ancient", 120)])
    await db_session.commit()
    assert step(await get(admin_headers, 90), "signed_up")["count"] == 1
    assert step(await get(admin_headers, 200), "signed_up")["count"] == 2


@pytest.mark.asyncio
async def test_empty_window(db_session, admin_headers):
    body = await get(admin_headers)
    assert body["cohorts"] == []
    assert step(body, "signed_up")["count"] == 0
    assert step(body, "signed_up")["pct_of_first"] is None


@pytest.mark.asyncio
async def test_retention_uses_exact_day_and_null_for_immature(db_session, admin_headers):
    today = datetime.now(timezone.utc).date()
    mature = [make_user(f"m{i}", 40) for i in range(2)]
    young = make_user("young", 0)
    seed = make_user("seedret", 40, domain="lexilingo.test")
    db_session.add_all([*mature, young, seed])
    await db_session.commit()
    signup = (today - timedelta(days=40))
    db_session.add_all([
        DailyActivity(user_id=mature[0].id, activity_date=signup + timedelta(days=1)),
        DailyActivity(user_id=mature[0].id, activity_date=signup + timedelta(days=30)),
        DailyActivity(user_id=mature[1].id, activity_date=signup + timedelta(days=2)),
        DailyActivity(user_id=seed.id, activity_date=signup + timedelta(days=1)),
        DailyActivity(user_id=young.id, activity_date=today),
    ])
    await db_session.commit()

    cohorts = {c["week_start"]: c for c in (await get(admin_headers))["cohorts"]}
    old_week = (signup - timedelta(days=signup.weekday())).isoformat()
    young_week = (today - timedelta(days=today.weekday())).isoformat()

    m = cohorts[old_week]
    assert m["size"] == 2
    assert m["d1"] == {"eligible": 2, "retained": 1, "rate": 50.0}
    assert m["d7"] == {"eligible": 2, "retained": 0, "rate": 0.0}
    assert m["d30"] == {"eligible": 2, "retained": 1, "rate": 50.0}

    y = cohorts[young_week]
    assert y["size"] == 1
    for h in ("d1", "d7", "d30"):
        assert y[h] == {"eligible": 0, "retained": 0, "rate": None}
