import pytest
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.core.cache import build_cache_key
from app.crud.gamification import WalletCRUD
from app.models.gamification import UserWallet, WalletTransaction
from app.models.notification import Notification
from app.models.rbac import Role
from app.models.reward_grant import UserRewardGrant
from app.models.user import User
from app.services.starter_reward_service import StarterRewardService
from app.core.firebase_auth import get_or_create_user_from_claims


@pytest.fixture
async def db_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        Role.__table__,
        User.__table__,
        UserWallet.__table__,
        WalletTransaction.__table__,
        Notification.__table__,
        UserRewardGrant.__table__,
    ]
    async with engine.begin() as connection:
        await connection.run_sync(
            lambda sync_connection: Base.metadata.create_all(
                sync_connection,
                tables=tables,
            )
        )

    factory = sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )
    async with factory() as session:
        yield session
    await engine.dispose()


@pytest.fixture
async def test_user(db_session):
    user = User(
        email="starter@example.com",
        username="starter_user",
        hashed_password="not-used",
        display_name="Starter User",
        provider=["local"],
    )
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    return user


async def test_grant_new_user_reward_adds_100_gems_once(
    db_session,
    test_user,
):
    grant = await StarterRewardService.grant_new_user_reward(
        db_session,
        test_user.id,
    )
    await db_session.commit()

    assert grant.reward_key == "new_user_starter_gems_v1"
    assert grant.gems_awarded == 100

    wallet = (
        await db_session.execute(
            select(UserWallet).where(UserWallet.user_id == test_user.id)
        )
    ).scalar_one()
    assert wallet.gems == 100
    assert wallet.total_gems_earned == 100

    await StarterRewardService.grant_new_user_reward(
        db_session,
        test_user.id,
    )
    await db_session.commit()

    transaction_count = (
        await db_session.execute(
            select(func.count(WalletTransaction.id)).where(
                WalletTransaction.user_id == test_user.id,
                WalletTransaction.source == "new_user_starter_reward",
            )
        )
    ).scalar_one()
    notification_count = (
        await db_session.execute(
            select(func.count(Notification.id)).where(
                Notification.user_id == test_user.id,
                Notification.type == "starter_reward",
            )
        )
    ).scalar_one()

    assert wallet.gems == 100
    assert transaction_count == 1
    assert notification_count == 1


async def test_mark_seen_is_idempotent(db_session, test_user):
    await StarterRewardService.grant_new_user_reward(db_session, test_user.id)
    await db_session.commit()

    first = await StarterRewardService.mark_seen(db_session, test_user.id)
    second = await StarterRewardService.mark_seen(db_session, test_user.id)

    assert first is not None
    assert first.popup_seen_at is not None
    assert second is not None
    assert second.popup_seen_at == first.popup_seen_at

    grants = (
        await db_session.execute(
            select(UserRewardGrant).where(
                UserRewardGrant.user_id == test_user.id
            )
        )
    ).scalars().all()
    assert len(grants) == 1


async def test_add_gems_invalidates_wallet_cache(
    db_session,
    test_user,
    monkeypatch,
):
    deleted = []

    async def fake_delete_cached(key):
        deleted.append(key)

    monkeypatch.setattr("app.crud.gamification.delete_cached", fake_delete_cached)

    await WalletCRUD.add_gems(
        db_session,
        test_user.id,
        100,
        source="test",
        description="test grant",
    )

    assert deleted == [build_cache_key("wallet", user_id=str(test_user.id))]


async def test_first_social_login_receives_reward_only_once(db_session):
    claims = {
        "email": "social@example.com",
        "uid": "social-user-id",
        "name": "Social User",
        "email_verified": True,
    }

    first_user = await get_or_create_user_from_claims(db_session, claims)
    second_user = await get_or_create_user_from_claims(db_session, claims)

    wallet = (
        await db_session.execute(
            select(UserWallet).where(UserWallet.user_id == first_user.id)
        )
    ).scalar_one()
    transaction_count = (
        await db_session.execute(
            select(func.count(WalletTransaction.id)).where(
                WalletTransaction.user_id == first_user.id,
                WalletTransaction.source == "new_user_starter_reward",
            )
        )
    ).scalar_one()

    assert second_user.id == first_user.id
    assert wallet.gems == 100
    assert transaction_count == 1
