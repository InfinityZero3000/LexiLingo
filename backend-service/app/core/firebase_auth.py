"""Firebase ID token verification helpers."""

from __future__ import annotations

import json
import logging
import uuid
from functools import lru_cache
from typing import Any, Dict, Optional

import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import get_password_hash_async
from app.models.rbac import Role
from app.models.user import RefreshToken, User
from app.services.starter_reward_service import StarterRewardService

logger = logging.getLogger(__name__)

# The sign-in methods the app offers. Any other Firebase method, such as email/password
# self-signup, yields a genuine token for an address its holder may not own.
_PROVIDER_TAGS = {"google.com": "google", "facebook.com": "facebook"}


@lru_cache(maxsize=1)
def _init_firebase_app() -> None:
    """Initialize Firebase Admin SDK once per process."""
    if firebase_admin._apps:  # type: ignore[attr-defined]
        return

    cred: Optional[credentials.Base] = None

    if settings.FIREBASE_CREDENTIALS_FILE:
        # Option 1: Load from file path (recommended)
        cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_FILE)
    elif settings.FIREBASE_CREDENTIALS_JSON:
        # Option 2: Load from JSON string
        try:
            cred = credentials.Certificate(json.loads(settings.FIREBASE_CREDENTIALS_JSON))
        except Exception as exc:  # pragma: no cover - defensive
            logger.error("Invalid FIREBASE_CREDENTIALS_JSON: %s", exc)
            raise
    else:
        logger.warning("Firebase credentials not provided; auth verification will fail.")
        raise RuntimeError("Missing Firebase credentials")

    firebase_admin.initialize_app(cred, {'projectId': settings.FIREBASE_PROJECT_ID})


def verify_firebase_token(id_token: str) -> Optional[Dict[str, Any]]:
    """Verify Firebase ID token and return claims, or None if invalid."""
    try:
        _init_firebase_app()
        decoded = firebase_auth.verify_id_token(id_token)
        return decoded
    except Exception as exc:  # pragma: no cover - firebase SDK errors
        logger.warning("Firebase token verification failed: %s", exc)
        return None


async def _get_role_id(db: AsyncSession, role_slug: str) -> Optional[uuid.UUID]:
    """Load a role id by slug."""
    result = await db.execute(select(Role).where(Role.slug == role_slug))
    role = result.scalar_one_or_none()
    return role.id if role else None


async def _generate_unique_username(db: AsyncSession, base_username: str) -> str:
    """Generate a unique username for first-time Google/Firebase logins."""
    username = base_username
    counter = 1

    while True:
        result = await db.execute(select(User).where(User.username == username))
        if not result.scalar_one_or_none():
            return username
        username = f"{base_username}{counter}"
        counter += 1


async def revoke_all_refresh_tokens(db: AsyncSession, user_id: uuid.UUID) -> None:
    # A new password must end every other session: a stolen refresh token kept renewing
    # access for its full 7 days after the owner reset the password.
    await db.execute(
        update(RefreshToken)
        .where(RefreshToken.user_id == user_id, RefreshToken.is_revoked.is_(False))
        .values(is_revoked=True)
    )


async def drop_unproven_credentials(user: User) -> None:
    """Remove the sign-in methods set by someone who never proved they own the address."""
    if user.has_local_auth:
        user.hashed_password = await get_password_hash_async(uuid.uuid4().hex)
    if "facebook" in (user.provider or []):
        user.provider = [p for p in user.provider if p != "facebook"]


async def get_or_create_user_from_claims(db: AsyncSession, claims: Dict[str, Any]) -> User:
    """Map Firebase claims to local User. Create user if missing."""
    email = claims.get("email")
    uid = claims.get("uid") or claims.get("sub")
    display_name = claims.get("name") or (email or "user")
    avatar_url = claims.get("picture")
    is_verified = claims.get("email_verified") is True

    if not email:
        raise ValueError("Firebase token missing email")

    sign_in_provider = (claims.get("firebase") or {}).get("sign_in_provider")
    provider_tag = _PROVIDER_TAGS.get(sign_in_provider)
    if provider_tag is None:
        raise ValueError("This sign-in method is not supported.")
    allowlisted_role = settings.get_admin_role_for_email(email) if is_verified else None

    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    # Firebase never marks a Facebook email verified. Such a claim may open its own
    # account and come back to it, but never walk into one made another way.
    if not is_verified and (
        provider_tag != "facebook" or (user and "facebook" not in (user.provider or []))
    ):
        raise ValueError("Email already registered. Please login with your existing method."
                         if user else "Email is not verified.")

    if user:
        updated = False

        if is_verified and not user.is_verified:
            await drop_unproven_credentials(user)
            await revoke_all_refresh_tokens(db, user.id)
            user.is_verified = True
            updated = True
        if provider_tag not in (user.provider or []):
            user.add_provider(provider_tag)
            updated = True
        if avatar_url and user.avatar_url != avatar_url:
            user.avatar_url = avatar_url
            updated = True
        if allowlisted_role:
            role_id = await _get_role_id(db, allowlisted_role)
            if role_id and user.role_id != role_id:
                user.role_id = role_id
                updated = True

        if updated:
            await db.commit()
            await db.refresh(user)
        return user

    username_base = (email.split("@", 1)[0]) if "@" in email else (uid or "user")
    generated_username = await _generate_unique_username(db, username_base)
    role_slug = allowlisted_role or "user"
    role_id = await _get_role_id(db, role_slug)

    user = User(
        email=email,
        username=generated_username,
        hashed_password=await get_password_hash_async(uuid.uuid4().hex),
        display_name=display_name,
        avatar_url=avatar_url,
        provider=[provider_tag],
        is_verified=is_verified,
        is_active=True,
        role_id=role_id,
        is_onboarding_completed=False,
    )

    db.add(user)
    await db.flush()
    if role_slug == "user":
        await StarterRewardService.grant_new_user_reward(db, user.id)
    await db.commit()
    await db.refresh(user)
    return user
