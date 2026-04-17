"""Authentication helpers for user-facing AI routes."""

from __future__ import annotations

import logging
import os
from typing import Any, Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from pydantic import BaseModel

logger = logging.getLogger(__name__)

_bearer = HTTPBearer(auto_error=False)


class AuthenticatedUser(BaseModel):
    """Authenticated user claims resolved from a verified token."""

    user_id: str
    token_type: str = "access"
    claims: dict[str, Any]


def _jwt_secret() -> str:
    # Prefer dedicated AI JWT secret, fallback to backend SECRET_KEY for compatibility.
    return (
        os.getenv("AI_JWT_SECRET_KEY")
        or os.getenv("JWT_SECRET_KEY")
        or os.getenv("SECRET_KEY")
        or ""
    )


def _jwt_algorithm() -> str:
    return os.getenv("AI_JWT_ALGORITHM", os.getenv("ALGORITHM", "HS256"))


def _jwt_leeway_seconds() -> int:
    raw = os.getenv("AI_JWT_LEEWAY_SECONDS", "15").strip()
    try:
        return max(0, int(raw))
    except ValueError:
        return 15


def _decode_backend_jwt(token: str) -> Optional[dict[str, Any]]:
    secret = _jwt_secret()
    if not secret:
        logger.error("JWT secret is not configured for AI service")
        return None

    try:
        payload = jwt.decode(
            token,
            secret,
            algorithms=[_jwt_algorithm()],
            options={
                "verify_aud": False,
                "leeway": _jwt_leeway_seconds(),
            },
        )
    except JWTError:
        return None

    sub = payload.get("sub")
    if not sub:
        return None

    token_type = payload.get("type")
    if token_type and token_type != "access":
        return None

    return payload


async def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> AuthenticatedUser:
    """Resolve the current user from Authorization Bearer token."""
    if not credentials or not credentials.credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Missing bearer token",
        )

    token = credentials.credentials.strip()
    payload = _decode_backend_jwt(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired authentication token",
        )

    return AuthenticatedUser(
        user_id=str(payload.get("sub")),
        token_type=str(payload.get("type") or "access"),
        claims=payload,
    )


def enforce_user_scope(
    current_user: AuthenticatedUser,
    requested_user_id: str | None,
) -> str:
    """Ensure path/body user_id cannot escape the authenticated identity."""
    normalized = (requested_user_id or "").strip()
    if normalized in {"", "demo_user", "anonymous", "unknown"}:
        return current_user.user_id

    if requested_user_id and str(requested_user_id) != current_user.user_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Forbidden: user scope mismatch",
        )
    return current_user.user_id
