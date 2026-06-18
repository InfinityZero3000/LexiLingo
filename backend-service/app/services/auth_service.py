import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import (
    create_access_token,
    create_refresh_token,
    get_password_hash_async,
    verify_password_async,
)
from app.models.rbac import Role
from app.models.user import RefreshToken, User
from app.schemas.auth import RegisterRequest


async def get_role_id(db: AsyncSession, role_slug: str) -> uuid.UUID | None:
    result = await db.execute(select(Role).where(Role.slug == role_slug))
    role = result.scalar_one_or_none()
    return role.id if role else None


async def ensure_unique_username(db: AsyncSession, base_username: str) -> str:
    username = base_username
    counter = 1
    while True:
        existing = (await db.execute(select(User).where(User.username == username))).scalar_one_or_none()
        if not existing:
            return username
        username = f"{base_username}{counter}"
        counter += 1


async def register_user(db: AsyncSession, request: RegisterRequest) -> User:
    """Create a new local user; caller must handle duplicate checks before calling."""
    from app.services.starter_reward_service import StarterRewardService

    role_id = await get_role_id(db, "user")
    user = User(
        email=request.email,
        username=request.username,
        hashed_password=await get_password_hash_async(request.password),
        display_name=request.display_name or request.username,
        role_id=role_id,
        provider=["local"],
        is_onboarding_completed=False,
    )
    db.add(user)
    await db.flush()
    await StarterRewardService.grant_new_user_reward(db, user.id)
    await db.commit()
    await db.refresh(user)
    return user


async def authenticate_user(
    db: AsyncSession, email: str, password: str, dummy_hash: str
) -> User | None:
    """Verify credentials and return the user, or None if invalid.

    dummy_hash is always run when the email is not found to prevent timing attacks.
    """
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()
    hash_to_check = user.hashed_password if (user and user.hashed_password) else dummy_hash
    password_ok = await verify_password_async(password, hash_to_check)
    if not user or not password_ok:
        return None
    return user


async def save_refresh_token(db: AsyncSession, user_id: uuid.UUID, token: str) -> None:
    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    db.add(RefreshToken(user_id=user_id, token=token, expires_at=expires_at))
    await db.commit()


async def revoke_refresh_token(db: AsyncSession, token: str) -> None:
    result = await db.execute(select(RefreshToken).where(RefreshToken.token == token))
    db_token = result.scalar_one_or_none()
    if db_token:
        db_token.is_revoked = True
        db_token.revoked_at = datetime.now(timezone.utc)
        await db.commit()


def issue_token_pair(user_id: str) -> tuple[str, str]:
    """Return (access_token, refresh_token) for a given user_id string."""
    return (
        create_access_token({"sub": user_id}),
        create_refresh_token({"sub": user_id}),
    )
