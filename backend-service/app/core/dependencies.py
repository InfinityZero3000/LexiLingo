"""
FastAPI dependencies

Reusable dependencies for authentication and authorization
"""

from typing import Optional
from fastapi import Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.security import decode_token
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
    
    # 1) Try local JWT (backward compatibility)
    payload = decode_token(token)
    if payload and (sub := payload.get("sub")):
        result = await db.execute(select(User).where(User.id == sub))
        user = result.scalar_one_or_none()
        if user and user.is_active:
            return user

    # 2) Try Firebase ID token
    claims = verify_firebase_token(token)
    if claims:
        try:
            user = await get_or_create_user_from_claims(db, claims)
            if user and user.is_active:
                return user
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
    
    # 1) Try local JWT
    payload = decode_token(token)
    if payload and (sub := payload.get("sub")):
        result = await db.execute(select(User).where(User.id == sub))
        user = result.scalar_one_or_none()
        if user and user.is_active:
            return user

    # 2) Try Firebase ID token
    claims = verify_firebase_token(token)
    if claims:
        try:
            user = await get_or_create_user_from_claims(db, claims)
            if user and user.is_active:
                return user
        except ValueError:
            pass  # Invalid token, return None
    
    return None
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid Firebase token payload",
            )
        if not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Inactive user"
            )
        return user

    # 3) Unauthorized
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Invalid authentication credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )


async def get_current_active_user(
    current_user: User = Depends(get_current_user)
) -> User:
    """
    Get current active user (for routes that require active users only).
    """
    if not current_user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Inactive user"
        )
    return current_user
