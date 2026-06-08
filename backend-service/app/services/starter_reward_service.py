"""New learner starter reward orchestration."""

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.crud.gamification import WalletCRUD
from app.models.notification import Notification
from app.models.reward_grant import UserRewardGrant
from app.models.user import UserDevice


class StarterRewardService:
    reward_key = "new_user_starter_gems_v1"
    gems_awarded = 100

    @classmethod
    async def grant_new_user_reward(
        cls,
        db: AsyncSession,
        user_id: UUID,
    ) -> UserRewardGrant:
        """Grant the starter reward without committing the outer transaction."""
        result = await db.execute(
            select(UserRewardGrant).where(
                UserRewardGrant.user_id == user_id,
                UserRewardGrant.reward_key == cls.reward_key,
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            return existing

        grant = UserRewardGrant(
            user_id=user_id,
            reward_key=cls.reward_key,
            gems_awarded=cls.gems_awarded,
        )
        try:
            async with db.begin_nested():
                db.add(grant)
                await db.flush()
        except IntegrityError:
            result = await db.execute(
                select(UserRewardGrant).where(
                    UserRewardGrant.user_id == user_id,
                    UserRewardGrant.reward_key == cls.reward_key,
                )
            )
            existing = result.scalar_one_or_none()
            if existing:
                return existing
            raise

        await WalletCRUD.add_gems(
            db,
            user_id,
            cls.gems_awarded,
            source="new_user_starter_reward",
            description="New learner starter gift",
            commit=False,
        )
        db.add(
            Notification(
                user_id=user_id,
                title="Welcome gift",
                body="100 Gems have been added to your wallet.",
                type="starter_reward",
                data={
                    "reward_key": cls.reward_key,
                    "gems": cls.gems_awarded,
                    "route": "/",
                },
            )
        )
        await db.flush()
        return grant

    @classmethod
    async def get_pending(
        cls,
        db: AsyncSession,
        user_id: UUID,
    ) -> UserRewardGrant | None:
        result = await db.execute(
            select(UserRewardGrant).where(
                UserRewardGrant.user_id == user_id,
                UserRewardGrant.reward_key == cls.reward_key,
                UserRewardGrant.popup_seen_at.is_(None),
            )
        )
        return result.scalar_one_or_none()

    @classmethod
    async def mark_seen(
        cls,
        db: AsyncSession,
        user_id: UUID,
    ) -> UserRewardGrant | None:
        result = await db.execute(
            select(UserRewardGrant).where(
                UserRewardGrant.user_id == user_id,
                UserRewardGrant.reward_key == cls.reward_key,
            )
        )
        grant = result.scalar_one_or_none()
        if grant and grant.popup_seen_at is None:
            grant.popup_seen_at = datetime.now(timezone.utc)
            await db.commit()
            await db.refresh(grant)
        return grant

    @classmethod
    async def deliver_pending_push(
        cls,
        db: AsyncSession,
        user_id: UUID,
        tokens: list[str] | None = None,
    ) -> bool:
        result = await db.execute(
            select(UserRewardGrant).where(
                UserRewardGrant.user_id == user_id,
                UserRewardGrant.reward_key == cls.reward_key,
                UserRewardGrant.push_sent_at.is_(None),
            )
        )
        grant = result.scalar_one_or_none()
        if not grant:
            return False

        clean_tokens = [token for token in (tokens or []) if token]
        if not clean_tokens:
            token_result = await db.execute(
                select(UserDevice.fcm_token).where(
                    UserDevice.user_id == user_id,
                    UserDevice.fcm_token.is_not(None),
                )
            )
            clean_tokens = [
                token for token in token_result.scalars().all() if token
            ]
        if not clean_tokens:
            return False

        from app.services.push_notification_service import (
            PushNotificationService,
        )

        delivered = await PushNotificationService().send_starter_reward(
            tokens=clean_tokens,
            gems=grant.gems_awarded,
            reward_key=grant.reward_key,
            title="Welcome gift",
            body=f"{grant.gems_awarded} Gems are waiting in your wallet.",
        )
        if delivered:
            grant.push_sent_at = datetime.now(timezone.utc)
            await db.commit()
        return delivered
