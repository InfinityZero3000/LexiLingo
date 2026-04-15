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
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import get_password_hash_async
from app.models.rbac import Role
from app.models.user import User

logger = logging.getLogger(__name__)


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


async def get_or_create_user_from_claims(db: AsyncSession, claims: Dict[str, Any]) -> User:
    """Map Firebase claims to local User. Create user if missing."""
    email = claims.get("email")
    uid = claims.get("uid") or claims.get("sub")
    display_name = claims.get("name") or (email or "user")
    avatar_url = claims.get("picture")
    is_verified = bool(claims.get("email_verified", False))
    allowlisted_role = settings.get_admin_role_for_email(email)

    if not email:
        raise ValueError("Firebase token missing email")

    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if user:
        updated = False

        if not user.has_google_auth:
            user.add_provider("google")
            updated = True
        if is_verified and not user.is_verified:
            user.is_verified = True
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
        provider=["google"],
        is_verified=is_verified,
        is_active=True,
        role_id=role_id,
        is_onboarding_completed=False,
    )

    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user
