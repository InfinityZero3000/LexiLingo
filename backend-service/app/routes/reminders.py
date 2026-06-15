"""Reminder preference API routes."""

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.reminder import UserReminderPreference
from app.models.user import User
from app.schemas.common import ApiResponse
from app.schemas.reminders import ReminderPreferenceResponse, ReminderPreferenceUpdate

router = APIRouter(prefix="/users/me/reminder-preferences", tags=["Reminder Preferences"])


def compute_next_check_at(
    time_text: str,
    timezone_name: str,
    now_utc: datetime | None = None,
) -> datetime:
    """Return the next UTC reminder check time for a local HH:MM preference."""
    now_utc = now_utc or datetime.now(timezone.utc)
    try:
        local_tz = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        local_tz = ZoneInfo(settings.REMINDER_DEFAULT_TIMEZONE)

    hour, minute = [int(part) for part in time_text.split(":")]
    local_now = now_utc.astimezone(local_tz)
    candidate = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if candidate <= local_now:
        candidate = candidate + timedelta(days=1)
    return candidate.astimezone(timezone.utc)


async def _get_or_create_preferences(
    db: AsyncSession,
    user: User,
) -> UserReminderPreference:
    result = await db.execute(
        select(UserReminderPreference).where(UserReminderPreference.user_id == user.id)
    )
    preference = result.scalar_one_or_none()
    if preference:
        return preference

    preference = UserReminderPreference(
        user_id=user.id,
        enabled=True,
        push_enabled=True,
        next_check_at=compute_next_check_at("09:00", settings.REMINDER_DEFAULT_TIMEZONE),
    )
    db.add(preference)
    await db.commit()
    await db.refresh(preference)
    return preference


@router.get("", response_model=ApiResponse[ReminderPreferenceResponse])
async def get_reminder_preferences(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get or initialize current user's FSRS review reminder preferences."""
    preference = await _get_or_create_preferences(db, current_user)
    return ApiResponse(data=ReminderPreferenceResponse.model_validate(preference))


@router.put("", response_model=ApiResponse[ReminderPreferenceResponse])
async def update_reminder_preferences(
    update: ReminderPreferenceUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update current user's FSRS review reminder preferences."""
    preference = await _get_or_create_preferences(db, current_user)
    update_data = update.model_dump(exclude_unset=True)

    for field, value in update_data.items():
        setattr(preference, field, value)

    preference.next_check_at = compute_next_check_at(
        preference.reminder_time_local,
        preference.timezone,
    )
    preference.updated_at = datetime.now(timezone.utc)

    await db.commit()
    await db.refresh(preference)
    return ApiResponse(data=ReminderPreferenceResponse.model_validate(preference))
