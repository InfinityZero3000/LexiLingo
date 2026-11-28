"""Report-only quality checks for one course: CEFR level fit and skill balance."""
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_resource
from app.models.user import User
from app.services.cefr_level_fit import (
    LEVELS,
    course_balance,
    course_level_fit,
    load_course_views,
    load_lexicon,
)

router = APIRouter(prefix="/admin/courses", tags=["Admin"])


@router.get("/{course_id}/quality")
async def course_quality(
    course_id: UUID,
    db: AsyncSession = Depends(get_db),
    admin_user: User = Depends(require_resource("courses")),
) -> dict:
    views = await load_course_views(db, course_id)
    if not views:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Course not found")
    view = views[0]
    fit = course_level_fit(view, await load_lexicon(db))
    profile = fit.pop("profile")
    total = profile["listed"] or 1
    return {
        "success": True,
        "data": {
            "course_id": str(course_id),
            "title": view["title"],
            "level_fit": {
                **fit,
                "distribution": {level: round(profile["counts"][level] / total, 4) for level in LEVELS},
                "unlisted": profile["unlisted"],
            },
            "balance": course_balance(view),
        },
    }
