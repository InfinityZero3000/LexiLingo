"""
FastAPI dependencies

Reusable dependencies for authentication, authorization, and RBAC
"""

import uuid
from typing import Optional

import anyio
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.database import get_db
from app.core.security import decode_token
from app.core.token_blacklist import TokenBlacklist
from app.core.firebase_auth import verify_firebase_token, get_or_create_user_from_claims
from app.models.user import User

# HTTP Bearer token scheme
security = HTTPBearer()
optional_security = HTTPBearer(auto_error=False)


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    Get current authenticated user from JWT token (REQUIRED).
    
    Usage in routes:
        @router.get("/me")
        async def get_me(current_user: User = Depends(get_current_user)):
            return current_user
    """
    token = credentials.credentials
    if await TokenBlacklist.is_blacklisted(token):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token"
        )
    
    # 1) Try local JWT (backward compatibility)
    payload = decode_token(token)
    if payload and payload.get("type") == "access" and (sub := payload.get("sub")):
        try:
            # Convert string to UUID for query
            user_id = uuid.UUID(sub) if isinstance(sub, str) else sub
            result = await db.execute(
                select(User).where(User.id == user_id).options(selectinload(User.role))
            )
            user = result.scalar_one_or_none()
            if user and user.is_active:
                return user
        except (ValueError, TypeError):
            pass  # Invalid UUID format, try Firebase next

    # 2) Try Firebase ID token
    claims = await anyio.to_thread.run_sync(verify_firebase_token, token)
    if claims:
        try:
            user = await get_or_create_user_from_claims(db, claims)
            if user and user.is_active:
                # Ensure role relationship is eagerly loaded to avoid async lazy-load
                # errors when response serializers access role_slug/role_level.
                result = await db.execute(
                    select(User)
                    .where(User.id == user.id)
                    .options(selectinload(User.role))
                )
                return result.scalar_one_or_none() or user
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication token"
            )
    
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication token"
    )


async def get_current_user_optional(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(optional_security),
    db: AsyncSession = Depends(get_db)
) -> Optional[User]:
    """
    Get current authenticated user if token is provided (OPTIONAL).
    Returns None if no token or invalid token.
    
    Usage in routes for public endpoints with optional auth:
        @router.get("/courses")
        async def get_courses(current_user: Optional[User] = Depends(get_current_user_optional)):
            # current_user will be None if not authenticated
            pass
    """
    if not credentials:
        return None
    
    token = credentials.credentials
    if await TokenBlacklist.is_blacklisted(token):
        return None
    
    # 1) Try local JWT
    payload = decode_token(token)
    if payload and payload.get("type") == "access" and (sub := payload.get("sub")):
        try:
            # Convert string to UUID for query
            user_id = uuid.UUID(sub) if isinstance(sub, str) else sub
            result = await db.execute(
                select(User).where(User.id == user_id).options(selectinload(User.role))
            )
            user = result.scalar_one_or_none()
            if user and user.is_active:
                return user
        except (ValueError, TypeError):
            pass  # Invalid UUID format, try Firebase next

    # 2) Try Firebase ID token
    claims = await anyio.to_thread.run_sync(verify_firebase_token, token)
    if claims:
        try:
            user = await get_or_create_user_from_claims(db, claims)
            if user and user.is_active:
                # Keep behavior consistent with required auth dependency.
                result = await db.execute(
                    select(User)
                    .where(User.id == user.id)
                    .options(selectinload(User.role))
                )
                return result.scalar_one_or_none() or user
        except ValueError:
            pass  # Invalid token, return None
    
    # 3) Invalid/unrecognized credentials — return None (optional auth contract)
    return None


# ── RBAC Guards ───────────────────────────────────────────


def _get_user_role_level(user: User) -> int:
    """Get the role level for a user. Defaults to 0 (regular user)."""
    if hasattr(user, "role_level"):
        return user.role_level
    if user.role and hasattr(user.role, "level"):
        return user.role.level
    return 0


async def get_current_admin(
    current_user: User = Depends(get_current_user),
) -> User:
    """
    Require admin or super_admin role.
    
    Usage:
        @router.post("/admin/courses")
        async def create_course(admin: User = Depends(get_current_admin)):
            ...
    """
    role_level = _get_user_role_level(current_user)
    if role_level < 1:  # admin=1, super_admin=2
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin privileges required",
        )
    return current_user

async def get_current_super_admin(
    current_user: User = Depends(get_current_user),
) -> User:
    """
    Require super_admin role only.
    
    Usage:
        @router.delete("/admin/users/{id}")
        async def delete_user(super_admin: User = Depends(get_current_super_admin)):
            ...
    """
    role_level = _get_user_role_level(current_user)
    if role_level < 2:  # super_admin=2
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Super admin privileges required",
        )
    return current_user
