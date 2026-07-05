"""Referral system endpoints."""

from __future__ import annotations

import secrets
import string
import logging
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.cache import build_cache_key, delete_cached
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.gamification import UserWallet, WalletTransaction
from app.models.user import User
from app.schemas.common import MessageResponse

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/referral", tags=["Referral"])

_REFERRAL_REWARD_GEMS = 50
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

    # Award gems to referrer
    referrer_wallet = (
        await db.execute(select(UserWallet).where(UserWallet.user_id == referrer.id))
    ).scalar_one_or_none()

    if referrer_wallet:
        referrer_wallet.gems += _REFERRAL_REWARD_GEMS
        db.add(
            WalletTransaction(
                user_id=referrer.id,
                transaction_type="referral_reward",
                amount=_REFERRAL_REWARD_GEMS,
                description=f"Referral reward for inviting {locked_user.username}",
            )
        )
    else:
        logger.warning("Referrer %s has no wallet; gems skipped", referrer.id)

    # Award gems to new user
    new_user_wallet = (
        await db.execute(select(UserWallet).where(UserWallet.user_id == locked_user.id))
    ).scalar_one_or_none()

    gems_awarded = 0
    if new_user_wallet:
        new_user_wallet.gems += _REFERRAL_REWARD_GEMS
        db.add(
            WalletTransaction(
                user_id=locked_user.id,
                transaction_type="referral_bonus",
                amount=_REFERRAL_REWARD_GEMS,
                description=f"Welcome bonus for using referral code {code.upper()}",
            )
        )
        gems_awarded = _REFERRAL_REWARD_GEMS
    else:
        logger.warning("New user %s has no wallet; gems skipped", locked_user.id)

    # Mark referral as claimed — set after wallet checks so the error path is clear
    locked_user.referred_by = referrer.id
    await db.commit()
    await delete_cached(build_cache_key("wallet", user_id=str(referrer.id)))
    await delete_cached(build_cache_key("wallet", user_id=str(locked_user.id)))
    logger.info("Referral claimed: %s referred %s", referrer.id, locked_user.id)

    return ClaimResponse(
        message=f"Referral code applied! You both received {_REFERRAL_REWARD_GEMS} gems.",
        gems_awarded=gems_awarded,
    )
