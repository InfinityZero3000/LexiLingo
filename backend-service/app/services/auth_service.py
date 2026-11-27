import time
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import (
    create_user_access_token,
    create_refresh_token,
    hash_refresh_token,
    get_password_hash_async,
    verify_password_async,
)
from app.models.rbac import Role
from app.services.user_lookup import find_user_by_email, normalize_email
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
        email=normalize_email(request.email),
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
    user = await find_user_by_email(db, email)
    hash_to_check = user.hashed_password if (user and user.hashed_password) else dummy_hash
    password_ok = await verify_password_async(password, hash_to_check)
    if not user or not password_ok:
        return None
    return user


async def refresh_lifetime_days(db: AsyncSession, user_id: uuid.UUID) -> int:
    """How long a refresh token issued to this user stays valid: shorter for admin roles."""
    privileged = (
        await db.execute(
            select(User.id)
            .join(Role, User.role_id == Role.id)
            .where(User.id == user_id, Role.level >= 1)
        )
    ).scalar_one_or_none()
    days = settings.REFRESH_TOKEN_EXPIRE_DAYS
    if privileged is not None:
        days = min(days, settings.REFRESH_TOKEN_EXPIRE_DAYS_PRIVILEGED)
    return days


async def issue_refresh_token(
    db: AsyncSession,
    user_id: uuid.UUID,
    family_id: uuid.UUID | None = None,
    *,
    commit: bool = True,
    auth_time: int | None = None,
) -> str:
    """Create a refresh token and store it, with the lifetime this user's role calls for.

    The JWT and the stored row must agree, so both are built here from one number: any
    route that issues a session goes through this instead of pairing the two calls itself.
    """
    days = await refresh_lifetime_days(db, user_id)
    claims = {"sub": str(user_id)}
    if auth_time is not None:
        claims["auth_time"] = auth_time
    token = create_refresh_token(claims, expires_days=days)
    await save_refresh_token(db, user_id, token, family_id, commit=commit, lifetime_days=days)
    return token


async def save_refresh_token(
    db: AsyncSession,
    user_id: uuid.UUID,
    token: str,
    family_id: uuid.UUID | None = None,
    *,
    commit: bool = True,
    lifetime_days: int | None = None,
) -> None:
    days = settings.REFRESH_TOKEN_EXPIRE_DAYS if lifetime_days is None else lifetime_days
    expires_at = datetime.now(timezone.utc) + timedelta(days=days)
    db.add(
        RefreshToken(
            user_id=user_id,
            token_hash=hash_refresh_token(token),
            family_id=family_id or uuid.uuid4(),
            expires_at=expires_at,
        )
    )
    if commit:
        await db.commit()


async def find_refresh_token(
    db: AsyncSession, raw: str, *, for_update: bool = False
) -> RefreshToken | None:
    """Look a refresh token up by hash; rows written before the hash existed fall back to the raw value."""
    digest = hash_refresh_token(raw)
    for column, value in ((RefreshToken.token_hash, digest), (RefreshToken.token, raw)):
        query = select(RefreshToken).where(column == value)
        if for_update:
            query = query.with_for_update()
        row = (await db.execute(query)).scalar_one_or_none()
        if row is not None:
            if row.token_hash is None:
                row.token_hash = digest
            if row.family_id is None:
                row.family_id = uuid.uuid4()
            return row
    return None


async def revoke_refresh_family(db: AsyncSession, db_token: RefreshToken) -> None:
    now = datetime.now(timezone.utc)
    query = update(RefreshToken).values(is_revoked=True, revoked_at=now)
    if db_token.family_id is not None:
        query = query.where(
            RefreshToken.family_id == db_token.family_id, RefreshToken.is_revoked.is_(False)
        )
    else:
        query = query.where(RefreshToken.id == db_token.id)
    await db.execute(query)


async def issue_token_pair(
    db: AsyncSession, user_id: uuid.UUID, hashed_password: str | None
) -> tuple[str, str]:
    """A new sign-in: (access_token, refresh_token), the latter stored and role-aware."""
    now = int(time.time())
    return (
        create_user_access_token(user_id, hashed_password, auth_time=now),
        await issue_refresh_token(db, user_id, auth_time=now),
    )
