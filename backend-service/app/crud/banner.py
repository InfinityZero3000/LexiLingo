"""CRUD operations for Banner."""

from datetime import datetime, timezone
from typing import List, Optional
import uuid

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.banner import Banner

_CEFR_ORDER = {"A1": 0, "A2": 1, "B1": 2, "B2": 3, "C1": 4, "C2": 5}


def _level_in_range(level: Optional[str], min_level: Optional[str], max_level: Optional[str]) -> bool:
    """CEFR-range check used when filtering active banners in Python (small table)."""
    idx = _CEFR_ORDER.get((level or "A1").upper(), 0)
    if min_level and idx < _CEFR_ORDER.get(min_level.upper(), 0):
        return False
    if max_level and idx > _CEFR_ORDER.get(max_level.upper(), len(_CEFR_ORDER) - 1):
        return False
    return True


class BannerCRUD:
    @staticmethod
    async def create(db: AsyncSession, *, created_by_id: Optional[uuid.UUID], **data) -> Banner:
        banner = Banner(created_by_id=created_by_id, **data)
        db.add(banner)
        await db.commit()
        await db.refresh(banner)
        return banner

    @staticmethod
    async def get_by_id(db: AsyncSession, banner_id: uuid.UUID) -> Optional[Banner]:
        result = await db.execute(select(Banner).where(Banner.id == banner_id))
        return result.scalar_one_or_none()

    @staticmethod
    async def list_all(db: AsyncSession, *, skip: int = 0, limit: int = 100) -> List[Banner]:
        result = await db.execute(
            select(Banner)
            .order_by(Banner.priority.desc(), Banner.created_at.desc())
            .offset(skip)
            .limit(limit)
        )
        return list(result.scalars().all())

    @staticmethod
    async def list_active(
        db: AsyncSession,
        *,
        position: str,
        level: Optional[str] = None,
        language: Optional[str] = None,
    ) -> List[Banner]:
        now = datetime.now(timezone.utc)
        result = await db.execute(
            select(Banner)
            .where(
                Banner.is_active.is_(True),
                Banner.position == position,
                or_(Banner.start_at.is_(None), Banner.start_at <= now),
                or_(Banner.end_at.is_(None), Banner.end_at >= now),
                or_(Banner.target_language.is_(None), Banner.target_language == language),
            )
            .order_by(Banner.priority.desc(), Banner.created_at.desc())
        )
        banners = result.scalars().all()
        return [
            b for b in banners
            if _level_in_range(level, b.target_min_level, b.target_max_level)
        ]

    @staticmethod
    async def update(db: AsyncSession, banner_id: uuid.UUID, **fields) -> Optional[Banner]:
        banner = await BannerCRUD.get_by_id(db, banner_id)
        if not banner:
            return None
        for field, value in fields.items():
            setattr(banner, field, value)
        await db.commit()
        await db.refresh(banner)
        return banner

    @staticmethod
    async def delete(db: AsyncSession, banner_id: uuid.UUID) -> bool:
        banner = await BannerCRUD.get_by_id(db, banner_id)
        if not banner:
            return False
        await db.delete(banner)
        await db.commit()
        return True
