"""Mock data stays out of real databases, and what it writes agrees with itself."""
from datetime import datetime, timezone

import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.course import Course, Lesson, Unit
from app.models.games import XPTransaction
from app.models.progress import DailyActivity
from app.models.user import User
from scripts import seed_admin_mock
from scripts.seed_guard import MAX_REAL_ACCOUNTS, NotASandbox, require_sandbox


async def _add_users(db: AsyncSession, domain: str, count: int) -> None:
    for n in range(count):
        db.add(User(email=f"person{n}@{domain}", username=f"person{n}{domain}", hashed_password="x"))
    await db.flush()


@pytest.mark.asyncio
async def test_refused_when_the_database_holds_real_accounts(db_session: AsyncSession):
    await _add_users(db_session, "gmail.com", MAX_REAL_ACCOUNTS + 1)
    with pytest.raises(NotASandbox, match="real-looking accounts"):
        await require_sandbox(db_session)


@pytest.mark.asyncio
async def test_refused_in_production(db_session: AsyncSession, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "APP_ENV", "production")
    with pytest.raises(NotASandbox, match="production"):
        await require_sandbox(db_session)


@pytest.mark.asyncio
async def test_refused_for_a_remote_host_unless_named(db_session: AsyncSession, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(settings, "DATABASE_URL", "postgresql+asyncpg://u:p@postgres:5432/lexilingo")
    monkeypatch.delenv("ALLOW_MOCK_SEED_HOST", raising=False)
    with pytest.raises(NotASandbox, match="host 'postgres'"):
        await require_sandbox(db_session)
    monkeypatch.setenv("ALLOW_MOCK_SEED_HOST", "postgres")
    await require_sandbox(db_session)


@pytest.mark.asyncio
async def test_mock_data_is_repeatable_and_consistent(db_session: AsyncSession):
    course = Course(title="Sample", language="en", level="A1", is_published=True)
    db_session.add(course)
    await db_session.flush()
    unit = Unit(course_id=course.id, title="U", order_index=0)
    db_session.add(unit)
    await db_session.flush()
    for n in range(6):
        db_session.add(Lesson(course_id=course.id, unit_id=unit.id, title=f"L{n}", order_index=n,
                              lesson_type="lesson", xp_reward=10, pass_threshold=80))
    await db_session.flush()
    now = datetime.now(timezone.utc)

    async def totals() -> tuple[int, int, int, int]:
        mock = User.email.like(f"%@{seed_admin_mock.MOCK_DOMAIN}")
        ids = select(User.id).where(mock)
        users = await db_session.scalar(select(func.count()).select_from(User).where(mock))
        profile = await db_session.scalar(select(func.sum(User.total_xp)).where(mock))
        ledger = await db_session.scalar(select(func.sum(XPTransaction.amount)).where(XPTransaction.user_id.in_(ids)))
        daily = await db_session.scalar(select(func.sum(DailyActivity.xp_earned)).where(DailyActivity.user_id.in_(ids)))
        return users, profile, ledger, daily

    await seed_admin_mock.seed(db_session, now)
    first = await totals()
    await seed_admin_mock.seed(db_session, now)

    assert await totals() == first
    users, profile, ledger, daily = first
    assert users == seed_admin_mock.LEARNERS
    assert profile == ledger == daily > 0
