"""Firebase ID token verification helpers."""

from __future__ import annotations

import json
import logging
import os
import uuid
from functools import lru_cache
from typing import Any, Dict, Optional

import firebase_admin
from firebase_admin import auth as firebase_auth
from firebase_admin import credentials
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import get_password_hash
from app.models.user import User

logger = logging.getLogger(__name__)


@lru_cache(maxsize=1)
def _init_firebase_app() -> None:
    """Initialize Firebase Admin SDK once per process."""
    if firebase_admin._apps:  # type: ignore[attr-defined]
        return

    cred: Optional[credentials.Base] = None

    if settings.FIREBASE_CREDENTIALS_JSON:
        try:
            cred = credentials.Certificate(json.loads(settings.FIREBASE_CREDENTIALS_JSON))
        except Exception as exc:  # pragma: no cover - defensive
            logger.error("Invalid FIREBASE_CREDENTIALS_JSON: %s", exc)
            raise
    elif "FIREBASE_CREDENTIALS_FILE" in os.environ:
        cred = credentials.Certificate(os.environ["FIREBASE_CREDENTIALS_FILE"])
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


async def get_or_create_user_from_claims(db: AsyncSession, claims: Dict[str, Any]) -> User:
    """Map Firebase claims to local User. Create user if missing."""
    from sqlalchemy import select

    email = claims.get("email")
    uid = claims.get("uid") or claims.get("sub")
    display_name = claims.get("name") or (email or "user")

    if not email:
        raise ValueError("Firebase token missing email")

    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if user:
        return user

    # Create a new user with generated username and placeholder password hash
    username_base = (email.split("@", 1)[0]) if "@" in email else (uid or "user")
    generated_username = f"{username_base}_{uuid.uuid4().hex[:6]}"

    user = User(
        email=email,
        username=generated_username,
        hashed_password=get_password_hash(uuid.uuid4().hex),
        display_name=display_name,
        is_verified=bool(claims.get("email_verified", True)),
        is_active=True,
    )

    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user
