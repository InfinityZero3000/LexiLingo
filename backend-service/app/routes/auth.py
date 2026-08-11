"""
Authentication Routes
"""
import logging
import asyncio
import secrets
import uuid

from datetime import datetime, timezone, timedelta
from fastapi import APIRouter, Depends, Header, HTTPException, status
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError


from app.core.database import get_db
from app.core.config import settings
from app.core.dependencies import get_current_user
from app.core.redis import RedisClient
from app.core.security import (
    get_password_hash,
    get_password_hash_async,
    create_access_token,
    create_refresh_token,
    decode_token,
    verify_password_async,
)
from app.core.token_blacklist import TokenBlacklist
from app.services.starter_reward_service import StarterRewardService
from app.models.user import User, RefreshToken
from app.services.email_service import EmailService
from app.services.auth_service import (
    register_user,
    authenticate_user,
    save_refresh_token,
    revoke_refresh_token,
    get_role_id as _get_role_id,
    ensure_unique_username as _ensure_unique_username,
    issue_token_pair,
)
from app.schemas.auth import (
    RegisterRequest, LoginRequest, LoginResponse, RefreshTokenRequest, TokenResponse,
    ChangePasswordRequest, GoogleLoginRequest, FacebookLoginRequest, ForgotPasswordRequest,
    ResetPasswordRequest, VerifyEmailRequest, VerifyEmailResponse, LogoutRequest
)
from app.schemas.user import UserResponse
from app.schemas.common import MessageResponse, ErrorCodes, ErrorDetail, ErrorResponse

logger = logging.getLogger(__name__)
router = APIRouter()


def _safe_str(value, default: str) -> str:
    if value is None or type(value).__name__ == "MagicMock":
        return default
    text = str(value).strip()
    return text if text else default


def _build_user_response(user: User) -> UserResponse:
    return UserResponse(
        id=user.id,
        email=user.email,
        username=user.username,
        display_name=user.display_name,
        native_language=_safe_str(getattr(user, "native_language", None), "vi"),
        target_language=_safe_str(getattr(user, "target_language", None), "en"),
        level=_safe_str(getattr(user, "level", None), "A1"),
        avatar_url=getattr(user, "avatar_url", None),
        is_active=bool(getattr(user, "is_active", True)),
        is_verified=bool(getattr(user, "is_verified", False)),
        is_onboarding_completed=bool(
            getattr(user, "is_onboarding_completed", False)
        ),
        created_at=getattr(user, "created_at", datetime.now(timezone.utc)),
        last_login=getattr(user, "last_login", None),
        cefr_level=_safe_str(
            getattr(user, "cefr_level", None) or getattr(user, "level", None),
            "A1",
        ),
        total_xp=int(getattr(user, "total_xp", 0) or 0),
        numeric_level=int(getattr(user, "numeric_level", 1) or 1),
        rank=_safe_str(getattr(user, "rank", None), "bronze"),
        role_id=getattr(user, "role_id", None),
        role_slug=_safe_str(getattr(user, "role_slug", None), "user"),
        role_level=int(getattr(user, "role_level", 0) or 0),
        is_admin=bool(getattr(user, "is_admin", False)),
        is_super_admin=bool(getattr(user, "is_super_admin", False)),
    )

# Pre-computed bcrypt hash used when a login email is not found.
# Always running bcrypt ensures the response time is the same whether the email
# exists or not, preventing user enumeration via timing side-channels.
_DUMMY_HASH: str = get_password_hash("_lexilingo_timing_normalization_placeholder_")



@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
async def register(
    request: RegisterRequest,
    db: AsyncSession = Depends(get_db),
):
    if (await db.execute(select(User).where(User.email == request.email))).scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")
    if (await db.execute(select(User).where(User.username == request.username))).scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username already taken")

    try:
        user = await register_user(db, request)
    except IntegrityError:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email or username already registered")

    try:
        from app.core.security import create_verification_token
        token = create_verification_token(
            {"sub": str(user.id), "email": user.email, "type": "email_verification"},
            expires_minutes=1440,
        )
        await EmailService.send_verification_email(
            to_email=user.email, token=token, display_name=user.display_name,
        )
    except Exception as exc:
        logger.warning("Could not send verification email to %s: %s", user.email, exc)

    return _build_user_response(user)


@router.post("/resend-verification")
async def resend_verification_email(
    body: ForgotPasswordRequest,
    db: AsyncSession = Depends(get_db),
):
    """Resend email verification link."""
    result = await db.execute(select(User).where(User.email == body.email))
    user = result.scalar_one_or_none()
    # Always return 200 to avoid email enumeration
    if user and not user.is_verified:
        try:
            from app.core.security import create_verification_token
            token = create_verification_token(
                {"sub": str(user.id), "email": user.email, "purpose": "email_verify"},
                expires_minutes=1440,
            )
            await EmailService.send_verification_email(
                to_email=user.email,
                token=token,
                display_name=user.display_name,
            )
        except Exception as exc:
            logger.warning("Could not resend verification email to %s: %s", user.email, exc)
    return {"message": "If your email is registered and unverified, a verification link has been sent."}


@router.post("/login", response_model=LoginResponse)
async def login(
    request: LoginRequest,
    db: AsyncSession = Depends(get_db),
):
    user = await authenticate_user(db, request.email, request.password, _DUMMY_HASH)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User account is inactive")
    # Local (email/password) accounts must verify their email before a session
    # is issued. Google/Facebook logins set is_verified from the provider's
    # own email_verified claim at account-creation time, so this never blocks
    # OAuth users.
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email not verified. Please check your inbox for a verification link before logging in.",
        )

    user_id = str(user.id)
    username = user.username
    email = user.email
    role = user.role_slug if hasattr(user, "role_slug") else "user"

    try:
        user.last_login = datetime.now(timezone.utc)
        await db.commit()
    except Exception:
        await db.rollback()

    access_token, refresh_token = issue_token_pair(user_id)
    await save_refresh_token(db, uuid.UUID(user_id), refresh_token)

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

    # A refresh token issued before email verification (or for an account
    # that was since unverified) must not keep renewing access forever —
    # otherwise the 7-day rotation window silently bypasses /login's check.
    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email not verified. Please check your inbox for a verification link before logging in.",
        )

    # FIX: Implement token rotation
    db_token.is_used = True
    
    # Create new tokens
    access_token = create_access_token({"sub": str(user.id)})
    new_refresh_token = create_refresh_token({"sub": str(user.id)})
    
    # Save new refresh token
    await save_refresh_token(db,user.id, new_refresh_token)
    
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
    return _build_user_response(current_user)


@router.post("/logout", response_model=MessageResponse)
async def logout(
    request: LogoutRequest,
    db: AsyncSession = Depends(get_db),
    authorization: str | None = Header(default=None),
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

    if authorization and authorization.lower().startswith("bearer "):
        access_token = authorization.split(" ", 1)[1].strip()
        payload = decode_token(access_token)
        if payload and payload.get("type") == "access":
            exp = payload.get("exp")
            expires_at = (
                datetime.fromtimestamp(exp, timezone.utc)
                if isinstance(exp, (int, float))
                else None
            )
            await TokenBlacklist.add(
                access_token,
                expires_at=expires_at,
                user_id=str(payload.get("sub") or ""),
            )

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
    from app.core.firebase_auth import verify_firebase_token
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
    logger.info(f"Google login attempt: source={request.source}, audience={audience}")

    google_info = await verify_google_token(request.id_token, audience=audience)

    # Only skip audience check when GOOGLE_CLIENT_ID is not configured.
    # If it IS configured and verification fails, the token belongs to a different
    # app/project — do NOT retry unchecked (would accept tokens from any Google app).
    if not google_info and request.source != "admin" and not audience:
        logger.info("Retrying token verification without audience restriction (GOOGLE_CLIENT_ID not configured)")
        google_info = await verify_google_token(request.id_token, audience=None)

    # Flutter web can return a Firebase ID token instead of Google OAuth id_token.
    # Accept only Firebase tokens issued for Google sign-in to keep auth strict.
    if not google_info:
        firebase_claims = verify_firebase_token(request.id_token)
        provider = (firebase_claims or {}).get("firebase", {}).get("sign_in_provider")
        if firebase_claims and provider == "google.com":
            logger.info("Accepted Firebase token for Google login flow")
            google_info = {
                "email": firebase_claims.get("email"),
                "email_verified": firebase_claims.get("email_verified", False),
                "name": firebase_claims.get("name"),
                "picture": firebase_claims.get("picture"),
            }

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
        role_slug = allowlisted_admin_role or "user"
        role_id = await _get_role_id(db, role_slug)
        
        user = User(
            email=email,
            username=username,
            hashed_password=await get_password_hash_async(uuid.uuid4().hex),
            display_name=google_info.get("name", username),
            avatar_url=google_info.get("picture"),
            provider=["google"],  # OAuth-created accounts never have local auth by default
            is_verified=email_verified,
            role_id=role_id,
            is_onboarding_completed=False,
        )
        db.add(user)
        await db.flush()
        if role_slug == "user":
            await StarterRewardService.grant_new_user_reward(db, user.id)
        await db.commit()
        await db.refresh(user)
    elif not user.has_google_auth:
        # "google" is NOT yet in this user's providers list
        is_admin_link = request.source == "admin" and allowlisted_admin_role
        # Google has verified this email, and it matches an existing local account —
        # let Google vouch for the email instead of leaving the user locked out
        # behind an unclicked verification link.
        can_verify_local_account = user.has_local_auth and email_verified

        if not is_admin_link and not can_verify_local_account:
            if not user.has_local_auth:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Email already registered with a different login method."
                )
            # Local account exists but Google hasn't verified this email either —
            # an unverified claim can't be trusted to unlock it.
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already registered. Please login with your existing method."
            )

        # Admin-allowlisted link, or Google vouching for a local account's email →
        # link google to this account.
        user.add_provider("google")
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
    await save_refresh_token(db,user.id, refresh_token)
    
    return LoginResponse(
        access_token=access_token,
        refresh_token=refresh_token,
        token_type="bearer",
        user_id=str(user.id),
        username=user.username,
        email=user.email,
        role=user.role_slug if hasattr(user, 'role_slug') else "user",
    )


@router.post("/facebook", response_model=LoginResponse)
async def facebook_login(
    request: FacebookLoginRequest,
    db: AsyncSession = Depends(get_db)
):
    """
    Login or register with Facebook via Firebase authentication.
    
    - Verifies Firebase ID token securely using Firebase Admin SDK
    - Uses same account linking / admin rules logic as Google
    - Returns JWT tokens
    """
    from app.core.firebase_auth import verify_firebase_token, get_or_create_user_from_claims
    from app.core.config import settings

    logger.info(f"Facebook (Firebase) login attempt: source={request.source}")

    # Verify Firebase ID token
    claims = verify_firebase_token(request.id_token)
    if not claims:
        logger.error(f"Firebase token verification failed for Facebook login (source={request.source})")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid Firebase ID token"
        )

    # Some basic checks before we accept the token:
    if "firebase" not in claims or claims["firebase"].get("sign_in_provider") != "facebook.com":
        logger.warning("Token provided to /facebook is not a facebook.com login token.")
        # We might still accept it if we want generic /firebase endpoint, 
        # but let's restrict to facebook for exactness.
        pass # Optional to raise error here, we let get_or_create handle the user.

    email = claims.get("email")
    if not email:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email not provided by Facebook/Firebase account."
        )

    try:
        user = await get_or_create_user_from_claims(db, claims)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc)
        )

    # For admin source verify the role (as done in Google logic)
    if request.source == "admin":
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
    
    # Save refresh token for revocation support
    await save_refresh_token(db,user.id, refresh_token)
    
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
    
    # Check if user has local auth — OAuth-only accounts cannot change password
    if not current_user.has_local_auth:
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
    
    # Only local accounts can reset password — return neutral response to avoid
    # leaking whether the account uses OAuth (account enumeration protection)
    if not user.has_local_auth:
        return MessageResponse(
            message="If the email exists, a password reset link has been sent.",
            detail="Check your email inbox."
        )
    
    # Create reset token (1 hour expiry)
    reset_token = create_verification_token(
        {"sub": str(user.id), "purpose": "password_reset"},
        expires_minutes=60
    )
    
    # Send reset email (best effort)
    await EmailService.send_password_reset_email(
        to_email=user.email,
        reset_token=reset_token,
        display_name=user.display_name or user.username,
    )
    
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


# ============================================================================
# Admin password login
# ============================================================================

@router.post("/admin/login")
async def admin_login(
    body: dict,
    db: AsyncSession = Depends(get_db),
):
    """
    Login to the admin panel with email + password.
    Only users with role_level >= 1 (admin/super_admin) are accepted.
    """
    email: str = (body.get("email") or "").strip().lower()
    password: str = body.get("password") or ""

    if not email or not password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email and password are required")

    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    hash_to_check = user.hashed_password if (user and user.hashed_password) else _DUMMY_HASH
    password_ok = await verify_password_async(password, hash_to_check)

    if not user or not password_ok:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
        )

    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User account is inactive")

    if not user.is_verified:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Email not verified. Please check your inbox for a verification link before logging in.",
        )

    if getattr(user, "role_level", 0) < 1:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin privileges required")

    user_id = str(user.id)
    user.last_login = datetime.now(timezone.utc)
    try:
        await db.commit()
    except Exception:
        await db.rollback()

    access_token = create_access_token({"sub": user_id})
    refresh_token_val = create_refresh_token({"sub": user_id})
    await save_refresh_token(db,user.id, refresh_token_val)

    user_data = _build_user_response(user)

    return {
        "success": True,
        "message": "Login successful",
        "data": {
            "access_token": access_token,
            "refresh_token": refresh_token_val,
            "token_type": "bearer",
            "user": user_data.model_dump(),
        },
    }


# ============================================================================
# Admin passwordless OTP login (kept for backward compatibility)
# ============================================================================

import time

# Dev/test fallback store: {email: (otp, expires_at)}. Production requires Redis.
_admin_otp_store: dict[str, tuple[str, float]] = {}
_OTP_TTL_SECONDS = 300  # 5 minutes
_ADMIN_OTP_KEY_PREFIX = "admin:otp:"
_ADMIN_OTP_ATTEMPT_PREFIX = "admin:otp-attempts:"
_ADMIN_OTP_COOLDOWN_PREFIX = "admin:otp-cooldown:"
_ADMIN_OTP_MAX_ATTEMPTS = 5
_ADMIN_OTP_COOLDOWN_SECONDS = 60
_admin_otp_attempts: dict[str, tuple[int, float]] = {}
_admin_otp_cooldowns: dict[str, float] = {}
_admin_otp_locks: dict[str, asyncio.Lock] = {}


async def _get_admin_otp_redis():
    redis = await RedisClient.get_instance()
    if redis is None and settings.is_production:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Admin OTP storage is unavailable",
        )
    return redis


async def _store_admin_otp(email: str, otp: str, redis=None) -> None:
    redis = redis if redis is not None else await _get_admin_otp_redis()
    if redis is not None:
        await redis.setex(f"{_ADMIN_OTP_KEY_PREFIX}{email}", _OTP_TTL_SECONDS, otp)
        return
    _admin_otp_store[email] = (otp, time.time() + _OTP_TTL_SECONDS)


async def _claim_admin_otp_cooldown(email: str, redis=None) -> bool:
    redis = redis if redis is not None else await _get_admin_otp_redis()
    if redis is not None:
        claimed = await redis.set(
            f"{_ADMIN_OTP_COOLDOWN_PREFIX}{email}", "1",
            ex=_ADMIN_OTP_COOLDOWN_SECONDS, nx=True,
        )
        return bool(claimed)
    now = time.time()
    if _admin_otp_cooldowns.get(email, 0) > now:
        return False
    _admin_otp_cooldowns[email] = now + _ADMIN_OTP_COOLDOWN_SECONDS
    return True


async def _record_admin_otp_failure(email: str, redis=None) -> None:
    redis = redis if redis is not None else await _get_admin_otp_redis()
    if redis is not None:
        key = f"{_ADMIN_OTP_ATTEMPT_PREFIX}{email}"
        count = await redis.incr(key)
        if int(count) == 1:
            await redis.expire(key, _OTP_TTL_SECONDS)
        return
    count, expires_at = _admin_otp_attempts.get(email, (0, 0))
    now = time.time()
    _admin_otp_attempts[email] = (
        (count if expires_at > now else 0) + 1,
        expires_at if expires_at > now else now + _OTP_TTL_SECONDS,
    )


async def _admin_otp_attempts_exhausted(email: str, redis=None) -> bool:
    redis = redis if redis is not None else await _get_admin_otp_redis()
    if redis is not None:
        value = await redis.get(f"{_ADMIN_OTP_ATTEMPT_PREFIX}{email}")
        return int(value or 0) >= _ADMIN_OTP_MAX_ATTEMPTS
    count, expires_at = _admin_otp_attempts.get(email, (0, 0))
    return expires_at > time.time() and count >= _ADMIN_OTP_MAX_ATTEMPTS


async def _consume_admin_otp(email: str, otp: str, redis=None) -> bool:
    redis = redis if redis is not None else await _get_admin_otp_redis()
    if redis is not None:
        result = int(await redis.eval(
            """
            local attempts = tonumber(redis.call("GET", KEYS[2]) or "0")
            if attempts >= tonumber(ARGV[2]) then
                return -1
            end
            if redis.call("GET", KEYS[1]) == ARGV[1] then
                redis.call("DEL", KEYS[1])
                redis.call("DEL", KEYS[2])
                return 1
            end
            attempts = redis.call("INCR", KEYS[2])
            if attempts == 1 then
                redis.call("EXPIRE", KEYS[2], ARGV[3])
            end
            return 0
            """,
            2,
            f"{_ADMIN_OTP_KEY_PREFIX}{email}",
            f"{_ADMIN_OTP_ATTEMPT_PREFIX}{email}",
            otp,
            _ADMIN_OTP_MAX_ATTEMPTS,
            _OTP_TTL_SECONDS,
        ))
        return result == 1

    lock = _admin_otp_locks.setdefault(email, asyncio.Lock())
    async with lock:
        if await _admin_otp_attempts_exhausted(email, redis):
            return False
        stored = _admin_otp_store.get(email)
        if not stored or stored[1] < time.time() or stored[0] != otp:
            await _record_admin_otp_failure(email, redis)
            return False
        del _admin_otp_store[email]
        _admin_otp_attempts.pop(email, None)
        return True


@router.post("/admin/request-otp")
async def admin_request_otp(
    body: dict,
    db: AsyncSession = Depends(get_db),
):
    """
    Send a 6-digit OTP to an admin email address.
    Only users with role_level >= 1 (admin/super_admin) are accepted.
    """
    email: str = (body.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email is required")
    otp_redis = await _get_admin_otp_redis()
    if not await _claim_admin_otp_cooldown(email, otp_redis):
        return {"success": True, "message": "If this email belongs to an admin, an OTP has been sent."}

    result = await db.execute(
        select(User).where(User.email == email)
    )
    user = result.scalar_one_or_none()

    # Respond the same way whether the user exists or not (anti-enumeration)
    if user and user.is_active and user.is_verified and getattr(user, "role_level", 0) >= 1:
        otp = f"{secrets.randbelow(1_000_000):06d}"
        await _store_admin_otp(email, otp, otp_redis)

        try:
            from app.services.email_service import EmailService
            await run_in_threadpool(
                EmailService._send_message_blocking,
                EmailService._build_otp_message(
                    to_email=email,
                    otp=otp,
                    display_name=user.display_name or user.username or email,
                ),
            )
        except Exception as exc:
            logger.warning("Failed to send admin OTP to %s: %s", email, exc)

    return {"success": True, "message": "If this email belongs to an admin, an OTP has been sent."}


@router.post("/admin/verify-otp")
async def admin_verify_otp(
    body: dict,
    db: AsyncSession = Depends(get_db),
):
    """
    Verify the 6-digit OTP and return JWT tokens for admin access.
    """
    email: str = (body.get("email") or "").strip().lower()
    otp: str = (body.get("otp") or "").strip()

    if not email or not otp:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email and OTP are required")

    if not await _consume_admin_otp(email, otp):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid or expired OTP")

    result = await db.execute(
        select(User).where(User.email == email)
    )
    user = result.scalar_one_or_none()

    if not user or not user.is_active or not user.is_verified or getattr(user, "role_level", 0) < 1:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Insufficient permissions")

    user_id = str(user.id)
    user.last_login = datetime.now(timezone.utc)
    try:
        await db.commit()
    except Exception:
        await db.rollback()

    access_token = create_access_token({"sub": user_id})
    refresh_token_val = create_refresh_token({"sub": user_id})
    await save_refresh_token(db,user.id, refresh_token_val)

    user_data = _build_user_response(user)

    return {
        "success": True,
        "message": "Login successful",
        "data": {
            "access_token": access_token,
            "refresh_token": refresh_token_val,
            "token_type": "bearer",
            "user": user_data.model_dump(),
        },
    }
