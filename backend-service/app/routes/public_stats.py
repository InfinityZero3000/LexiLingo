"""Numbers the sign-up page may show without an account."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import get_cached, set_cached
from app.core.config import settings
from app.core.database import get_db
from app.core.real_users import real_user_clause
from app.models.progress import DailyActivity
from app.models.user import User

router = APIRouter()

CACHE_KEY = "public_stats:v1"


class PublicStats(BaseModel):
    learners: int
    lessons_completed_today: int
    show: bool


@router.get("/stats", response_model=PublicStats)
async def get_public_stats(db: AsyncSession = Depends(get_db)) -> PublicStats:
    """Real learners only; `show` stays false until the count is worth advertising."""
    cached = await get_cached(CACHE_KEY)
    if cached is not None:
        return PublicStats(**cached)

    learners = (
        await db.execute(select(func.count(User.id)).where(User.is_active.is_(True), real_user_clause()))
    ).scalar_one()
    lessons_today = (
        await db.execute(
            select(func.coalesce(func.sum(DailyActivity.lessons_completed), 0))
            .join(User, User.id == DailyActivity.user_id)
            .where(
                DailyActivity.activity_date == datetime.now(timezone.utc).date(),
                real_user_clause(),
            )
        )
    ).scalar_one()

    stats = PublicStats(
        learners=int(learners),
        lessons_completed_today=int(lessons_today),
        show=int(learners) >= settings.PUBLIC_STATS_MIN_LEARNERS,
    )
    await set_cached(CACHE_KEY, stats.model_dump(), ttl=settings.PUBLIC_STATS_CACHE_SECONDS)
    return stats
