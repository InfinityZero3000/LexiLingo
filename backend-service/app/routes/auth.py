"""
Authentication Routes
"""
import uuid

from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.core.security import verify_password_async, get_password_hash_async, create_access_token, create_refresh_token
from app.models.user import User, RefreshToken
from app.models.rbac import Role
from app.schemas.auth import (
    RegisterRequest, LoginRequest, LoginResponse, RefreshTokenRequest, TokenResponse,
    ChangePasswordRequest, GoogleLoginRequest, ForgotPasswordRequest, 
    ResetPasswordRequest, VerifyEmailRequest, VerifyEmailResponse, LogoutRequest
)
from app.schemas.user import UserResponse
from app.schemas.common import MessageResponse, ErrorCodes, ErrorDetail, ErrorResponse

router = APIRouter()

async def _save_refresh_token(db: AsyncSession, user_id: uuid.UUID, token: str):
    """Save refresh token to database for revocation/rotation support."""
    from app.core.config import settings
    expires_at = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    
    db_token = RefreshToken(
        user_id=user_id,
        token=token,
        expires_at=expires_at
    )
    db.add(db_token)
    await db.commit()

# ... rest of code ...


async def _get_role_id(db: AsyncSession, role_slug: str) -> uuid.UUID | None:
    """Load a role id from its slug."""
    result = await db.execute(select(Role).where(Role.slug == role_slug))
    role = result.scalar_one_or_none()
    return role.id if role else None


async def _ensure_unique_username(db: AsyncSession, base_username: str) -> str:
    """Keep usernames unique for Google-first accounts."""
    username = base_username
    counter = 1

    while True:
        result = await db.execute(select(User).where(User.username == username))
        if not result.scalar_one_or_none():
            return username
        username = f"{base_username}{counter}"
        counter += 1


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    request: RegisterRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Register a new user.
    
    - **email**: Valid email address
    - **username**: Unique username (3-50 chars)
    - **password**: Password (min 8 chars)
    """
    # Check if email exists
    result = await db.execute(
        select(User).where(User.email == request.email)
    )
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered"
        )
    
    # Check if username exists
    result = await db.execute(
        select(User).where(User.username == request.username)
    )
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already taken"
        )
    
    # Create new user
    role_id = None
    result = await db.execute(select(Role).where(Role.slug == "user"))
    role = result.scalar_one_or_none()
    if role:
        role_id = role.id

    user = User(
        email=request.email,
        username=request.username,
        hashed_password=await get_password_hash_async(request.password),
        display_name=request.display_name or request.username,
        role_id=role_id,
    )
    
    db.add(user)
    await db.commit()
    await db.refresh(user)
    
    return user


@router.post("/login", response_model=LoginResponse)
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Login with email and password.
    
    Returns JWT access token and refresh token.
    """
    # Find user by email
    result = await db.execute(
        select(User).where(User.email == request.email)
    )
    user = result.scalar_one_or_none()
    
    if not user or not user.hashed_password or not await verify_password_async(request.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is inactive"
        )
    
    # Cache user fields before the commit so they survive a rollback
    user_id = str(user.id)
    username = user.username
    email = user.email
    role = user.role_slug if hasattr(user, 'role_slug') else "user"

    # Update last login — best-effort, don't fail the login if DB is locked under load
    try:
        user.last_login = datetime.now(timezone.utc)
        await db.commit()
    except Exception:
        await db.rollback()
    
    # Create tokens
    access_token = create_access_token({"sub": user_id})
    refresh_token = create_refresh_token({"sub": user_id})
    
    # FIX: Save refresh token for revocation support
    await _save_refresh_token(db, uuid.UUID(user_id), refresh_token)
    
    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        user_id=user_id,
        username=username,
        email=email,
        role=role,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    request: RefreshTokenRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Refresh access token using refresh token.
    """
    from app.core.security import decode_token
    
    # Decode refresh token
    payload = decode_token(request.refresh_token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token"
        )
    
    # Verify token type
    token_type = payload.get("type")
    if token_type != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token type - expected refresh token"
        )
    
    # FIX: Verify token exists and is valid in DB
    result = await db.execute(
        select(RefreshToken).where(
            RefreshToken.token == request.refresh_token,
            RefreshToken.is_revoked == False,
            RefreshToken.is_used == False,
            RefreshToken.expires_at > datetime.now(timezone.utc)
        )
    )
    db_token = result.scalar_one_or_none()
    
    if not db_token:
        # Potential reuse attack or revoked token
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token"
        )

    user_id_str = payload.get("sub")
    if not user_id_str:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload"
        )

    try:
        user_id = uuid.UUID(user_id_str) if isinstance(user_id_str, str) else user_id_str
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload"
        )

    # Verify user exists
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found or inactive"
        )
    
    # FIX: Implement token rotation
    db_token.is_used = True
    
    # Create new tokens
    access_token = create_access_token({"sub": str(user.id)})
    new_refresh_token = create_refresh_token({"sub": str(user.id)})
    
    # Save new refresh token
    await _save_refresh_token(db, user.id, new_refresh_token)
    
    return TokenResponse(
        access_token=access_token,
        refresh_token=new_refresh_token,
        token_type="bearer"
    )


@router.get("/me", response_model=UserResponse)
async def get_current_user_via_auth(
    current_user: User = Depends(get_current_user)
):
    """
    Get current user profile via /auth/me endpoint.
    
    Note: This is an alias for /users/me for backward compatibility.
    Requires authentication.
    """
    return current_user


@router.post("/logout", response_model=MessageResponse)
async def logout(
    request: LogoutRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Logout user.
    """
    if request.refresh_token:
        # FIX: Revoke token in DB
        result = await db.execute(
            select(RefreshToken).where(RefreshToken.token == request.refresh_token)
        )
        db_token = result.scalar_one_or_none()
        if db_token:
            db_token.is_revoked = True
            db_token.revoked_at = datetime.now(timezone.utc)
            await db.commit()

    return MessageResponse(
        message="Logged out successfully",
        detail="Session revoked and refresh token invalidated."
    )


@router.post("/google", response_model=LoginResponse)
async def google_login(
    request: GoogleLoginRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Login or register with Google OAuth.
    
    - Verifies Google ID token
    - Creates new user if not exists
    - Returns JWT tokens
    """
    from app.core.security import verify_google_token
    from app.core.config import settings
    
    # Select the correct Client ID based on source
    if request.source == "admin":
        audience = settings.GOOGLE_ADMIN_CLIENT_ID
        if not audience:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Admin Google OAuth not configured"
            )
    else:
        # For Flutter app: mobile sends token with aud=GOOGLE_CLIENT_ID;
        # Flutter web (Firebase Auth) sends token with aud=Firebase web client ID.
        # We try strict audience first, then fall back to no-audience check.
        audience = settings.GOOGLE_CLIENT_ID  # None is also accepted below
    
    # Verify Google token with the correct audience
    import logging
    logger = logging.getLogger(__name__)
    logger.info(f"Google login attempt: source={request.source}, audience={audience}")
    logger.info(f"id_token length={len(request.id_token)}, first_50={request.id_token[:50]}...")
    
    google_info = await verify_google_token(request.id_token, audience=audience)

    # For non-admin sources, if strict-audience check failed, retry without audience
    # (handles Firebase web id_tokens whose aud != GOOGLE_CLIENT_ID)
    if not google_info and request.source != "admin":
        logger.info("Retrying token verification without audience restriction (Flutter web / Firebase)")
        google_info = await verify_google_token(request.id_token, audience=None)

    if not google_info:
        logger.error(f"Google token verification returned None for source={request.source}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Google ID token"
        )
    
    email = google_info.get("email")
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email not provided by Google"
        )

    allowlisted_admin_role = settings.get_admin_role_for_email(email)
    email_verified = bool(google_info.get("email_verified", False))
    
    # Check if user exists
    result = await db.execute(
        select(User).where(User.email == email)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        if request.source == "admin" and not allowlisted_admin_role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Email is not allowlisted for admin access."
            )

        username = await _ensure_unique_username(db, email.split("@")[0])
        role_slug = allowlisted_admin_role if request.source == "admin" else "user"
        role_id = await _get_role_id(db, role_slug)
        
        user = User(
            email=email,
            username=username,
            hashed_password=await get_password_hash_async("OAUTH_USER_NO_PASSWORD"),
            display_name=google_info.get("name", username),
            avatar_url=google_info.get("picture"),
            provider="google",
            is_verified=email_verified,
            role_id=role_id,
        )
        db.add(user)
        await db.commit()
        await db.refresh(user)
    elif user.provider != "google":
        # FIX: Only update provider if it's currently 'local' or not 'google' 
        # but DON'T error out if it's an admin source (allows linking)
        if request.source != "admin" or not allowlisted_admin_role:
            if user.provider != "local": # If already set to something else (e.g. facebook)
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail=f"Email already registered with {user.provider}. Please login accordingly."
                )
            # For non-admin, still error to prevent accidental provider switch
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered with password. Please login with password."
            )

        # For admin, we allow switching to google provider to enable admin panel access
        user.provider = "google"
        user.is_verified = email_verified or user.is_verified
        user.avatar_url = google_info.get("picture") or user.avatar_url

    if request.source == "admin" and allowlisted_admin_role:
        target_role_id = await _get_role_id(db, allowlisted_admin_role)
        if target_role_id and user.role_id != target_role_id:
            user.role_id = target_role_id
    
    # For admin source, verify user has admin or super_admin role
    if request.source == "admin":
        await db.commit()

        # Load user with role relationship to get role_slug
        await db.refresh(user, ["role"])
        user_role = user.role.slug if user.role else None
        
        if user_role not in ["admin", "super_admin"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied. Admin privileges required."
            )
    
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="User account is inactive"
        )
    
    # Update last login
    user.last_login = datetime.now(timezone.utc)
    await db.commit()
    
    # Create tokens
    access_token = create_access_token({"sub": str(user.id)})
    refresh_token = create_refresh_token({"sub": str(user.id)})
    
    # FIX: Save refresh token for revocation support
    await _save_refresh_token(db, user.id, refresh_token)
    
    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        user_id=str(user.id),
        username=user.username,
        email=user.email,
        role=user.role_slug if hasattr(user, 'role_slug') else "user",
    )


@router.post("/change-password", response_model=MessageResponse)
async def change_password(
    request: ChangePasswordRequest,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Change password for authenticated user.
    
    Requires current password verification.
    """
    # Verify current password
    if not await verify_password_async(request.current_password, current_user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Current password is incorrect"
        )
    
    # Check if user is OAuth user
    if current_user.provider != "local":
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot change password for OAuth accounts"
        )
    
    # Update password
    current_user.hashed_password = await get_password_hash_async(request.new_password)
    current_user.updated_at = datetime.now(timezone.utc)
    await db.commit()
    
    return MessageResponse(
        message="Password changed successfully",
        detail="Please login again with your new password."
    )


@router.post("/forgot-password", response_model=MessageResponse)
async def forgot_password(
    request: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Request password reset email.
    
    Generates a reset token and sends email (stubbed for development).
    """
    from app.core.security import create_verification_token
    import logging
    
    # Find user by email
    result = await db.execute(
        select(User).where(User.email == request.email)
    )
    user = result.scalar_one_or_none()
    
    # Always return success to prevent email enumeration
    if not user:
        return MessageResponse(
            message="If the email exists, a password reset link has been sent.",
            detail="Check your email inbox."
        )
    
    # Check if OAuth user
    if user.provider != "local":
        return MessageResponse(
            message="This email is registered with Google. Please use Google login.",
            detail="Password reset is not available for OAuth accounts."
        )
    
    # Create reset token (1 hour expiry)
    reset_token = create_verification_token(
        {"sub": str(user.id), "purpose": "password_reset"},
        expires_minutes=60
    )
    
    # TODO: Send email with reset link
    # For now, log the token for development
    logging.info(f"Password reset token for {user.email}: {reset_token}")
    
    return MessageResponse(
        message="If the email exists, a password reset link has been sent.",
        detail="Check your email inbox."
    )


@router.post("/reset-password", response_model=MessageResponse)
async def reset_password(
    request: ResetPasswordRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Reset password using token from email.
    """
    from app.core.security import decode_verification_token
    
    # Verify token
    user_id = decode_verification_token(request.token, "password_reset")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired reset token"
        )
    
    # Find user
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Update password
    user.hashed_password = await get_password_hash_async(request.new_password)
    user.updated_at = datetime.now(timezone.utc)
    await db.commit()
    
    return MessageResponse(
        message="Password reset successfully",
        detail="You can now login with your new password."
    )


@router.post("/verify-email", response_model=VerifyEmailResponse)
async def verify_email(
    request: VerifyEmailRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Verify email using token.
    """
    from app.core.security import decode_verification_token
    
    # Verify token
    user_id = decode_verification_token(request.token, "email_verify")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid or expired verification token"
        )
    
    # Find user
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    if user.is_verified:
        return VerifyEmailResponse(
            verified=True,
            message="Email already verified"
        )
    
    # Verify user
    user.is_verified = True
    user.updated_at = datetime.now(timezone.utc)
    await db.commit()
    
    return VerifyEmailResponse(
        verified=True,
        message="Email verified successfully"
    )
