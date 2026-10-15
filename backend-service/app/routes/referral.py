"""Referral system endpoints."""

from __future__ import annotations

import secrets
import string
import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import build_cache_key, delete_cached
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.crud.gamification import WalletCRUD
from app.models.gamification import WalletTransaction
from app.models.user import User

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/referral", tags=["Referral"])

_REFERRAL_REWARD_GEMS = 50
# A referral rewards bringing someone new. Without a window, two established
# accounts could each claim the other's code for 100 gems apiece.
_CLAIM_WINDOW = timedelta(days=7)
# Each new account needs a verified email, but plus-addressing makes those free
# (a+1@gmail.com, a+2@…), so one person can mint referrals for their own main
# account. Past this many a day the claimer still gets their welcome bonus and
# the link is still recorded; only the referrer stops being paid.
# ponytail: per-referrer daily count; normalise plus-addressed emails at
# registration if farming shows up past the cap.
_MAX_REWARDED_REFERRALS_PER_DAY = 10
_REFERRER_REWARD_SOURCE = "referral_reward"
_ALPHABET = string.ascii_uppercase + string.digits


def _generate_code() -> str:
    return "".join(secrets.choice(_ALPHABET) for _ in range(8))


class ReferralInfoResponse(BaseModel):
    referral_code: str
    referral_link: str
    referred_by: UUID | None
    total_referrals: int


class ClaimResponse(BaseModel):
    message: str
    gems_awarded: int


@router.get("/my-code", response_model=ReferralInfoResponse)
async def get_my_referral_code(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ReferralInfoResponse:
    """Get or generate a referral code for the current user."""
    if not current_user.referral_code:
        for _ in range(10):
            code = _generate_code()
            existing = (
                await db.execute(select(User).where(User.referral_code == code))
            ).scalar_one_or_none()
            if not existing:
                current_user.referral_code = code
                await db.commit()
                break
        else:
            raise HTTPException(status_code=500, detail="Could not generate unique code")

    count: int = (
        await db.execute(
            select(func.count()).select_from(User).where(User.referred_by == current_user.id)
        )
    ).scalar_one()

    return ReferralInfoResponse(
        referral_code=current_user.referral_code,
        referral_link=f"https://lexilingo.app/referral/{current_user.referral_code}",
        referred_by=current_user.referred_by,
        total_referrals=count,
    )


@router.post("/claim/{code}", response_model=ClaimResponse)
async def claim_referral_code(
    code: str = Path(..., min_length=6, max_length=12),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ClaimResponse:
    """Claim a referral code. Can only be used once, and not on your own code."""
    # Re-fetch current user with a row-level lock to prevent concurrent double-claims.
    locked_user = (
        await db.execute(
            select(User).where(User.id == current_user.id).with_for_update()
        )
    ).scalar_one()

    if locked_user.referred_by is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="You have already used a referral code.",
        )

    referrer = (
        await db.execute(select(User).where(User.referral_code == code.upper()))
    ).scalar_one_or_none()

    if not referrer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid referral code.",
        )
    if referrer.id == locked_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot use your own referral code.",
        )
    if referrer.referred_by == locked_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="You cannot use the code of someone you referred.",
        )
    created_at = locked_user.created_at
    if created_at is not None and created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    if created_at is not None and now - created_at > _CLAIM_WINDOW:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Referral codes can only be used within 7 days of signing up.",
        )

    # WalletCRUD.add_gems locks the wallet row, creates a missing wallet and
    # bumps total_gems_earned. The inline `wallet.gems += …` this replaced did
    # none of that: concurrent claims on one referrer lost updates, and a user
    # with no wallet row was told "you both received 50 gems" and got nothing.
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    rewarded_today = (
        await db.execute(
            select(func.count(WalletTransaction.id)).where(
                WalletTransaction.user_id == referrer.id,
                WalletTransaction.source == _REFERRER_REWARD_SOURCE,
                WalletTransaction.created_at >= day_start,
            )
        )
    ).scalar() or 0
    if rewarded_today < _MAX_REWARDED_REFERRALS_PER_DAY:
        await WalletCRUD.add_gems(
            db,
            referrer.id,
            _REFERRAL_REWARD_GEMS,
            source=_REFERRER_REWARD_SOURCE,
            description=f"Referral reward for inviting {locked_user.username}",
            commit=False,
        )
    else:
        logger.warning(
            "Referrer %s hit the daily referral reward cap; not paid for %s",
            referrer.id, locked_user.id,
        )

    await WalletCRUD.add_gems(
        db,
        locked_user.id,
        _REFERRAL_REWARD_GEMS,
        source="referral_bonus",
        description=f"Welcome bonus for using referral code {code.upper()}",
        commit=False,
    )
    gems_awarded = _REFERRAL_REWARD_GEMS

    locked_user.referred_by = referrer.id
    await db.commit()
    await delete_cached(build_cache_key("wallet", user_id=str(referrer.id)))
    await delete_cached(build_cache_key("wallet", user_id=str(locked_user.id)))
    logger.info("Referral claimed: %s referred %s", referrer.id, locked_user.id)

    return ClaimResponse(
        message=f"Referral code applied! You both received {_REFERRAL_REWARD_GEMS} gems.",
        gems_awarded=gems_awarded,
    )
