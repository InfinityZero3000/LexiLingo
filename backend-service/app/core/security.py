"""
Security utilities

JWT token creation/validation and password hashing
"""

import asyncio
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any

import anyio
import bcrypt
import hashlib

import jwt

from app.core.config import settings


def _verify_password_sync(plain_password: str, hashed_password: str) -> bool:
    """Synchronous bcrypt verify — CPU-intensive, must be called in a thread."""
    try:
        return bcrypt.checkpw(
            plain_password.encode('utf-8'),
            hashed_password.encode('utf-8')
        )
    except (ValueError, TypeError):
        return False


async def verify_password_async(plain_password: str, hashed_password: str) -> bool:
    """Verify password in a thread pool to avoid blocking the event loop."""
    if not hashed_password:
        return False
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _verify_password_sync, plain_password, hashed_password)


def _hash_password_sync(password: str) -> str:
    """Synchronous bcrypt hash — CPU-intensive."""
    return bcrypt.hashpw(
        password.encode('utf-8'),
        bcrypt.gensalt()
    ).decode('utf-8')


def get_password_hash(password: str) -> str:
    """Hash a password (sync)."""
    return _hash_password_sync(password)


async def get_password_hash_async(password: str) -> str:
    """Hash a password in a thread pool to avoid blocking the event loop."""
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(None, _hash_password_sync, password)

def create_access_token(data: Dict[str, Any], expires_delta: Optional[timedelta] = None) -> str:
    """
    Create JWT access token.
    
    Args:
        data: Payload data (usually {"sub": user_id})
        expires_delta: Token expiration time
        
    Returns:
        Encoded JWT token
    """
    to_encode = data.copy()
    
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.now(timezone.utc),
        "jti": uuid.uuid4().hex,
        "type": "access",
        "iss": settings.JWT_ISSUER,
        "aud": settings.JWT_AUDIENCE,
    })
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM
    )
    
    return encoded_jwt


def create_refresh_token(data: Dict[str, Any]) -> str:
    """Create JWT refresh token with longer expiration."""
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.now(timezone.utc),
        "jti": uuid.uuid4().hex,
        "type": "refresh",
        "iss": settings.JWT_ISSUER,
        "aud": settings.JWT_AUDIENCE,
    })
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM
    )
    
    return encoded_jwt


def hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def decode_token(token: str) -> Optional[Dict[str, Any]]:
    """
    Decode and verify JWT token.
    
    Args:
        token: JWT token string
        
    Returns:
        Decoded payload or None if invalid
    """
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM],
            issuer=settings.JWT_ISSUER,
            audience=settings.JWT_AUDIENCE,
            options={"verify_iat": False},
        )
        return payload
    except jwt.PyJWTError:
        return None


def is_locally_issued_token(token: str) -> bool:
    """True when the JWT carries our own issuer (claims read without verifying).

    Only ever used to skip the Firebase verification path — never to grant
    access — so a forged `iss` costs the attacker a path, not us a check.
    """
    try:
        claims = jwt.decode(token, options={"verify_signature": False})
    except (jwt.PyJWTError, ValueError, AttributeError):
        return False
    return claims.get("iss") == settings.JWT_ISSUER


def create_verification_token(data: Dict[str, Any], expires_minutes: int = 60) -> str:
    """
    Create a verification token (for email verification, password reset).
    
    Args:
        data: Payload data (usually {"sub": user_id, "purpose": "email_verify"})
        expires_minutes: Token expiration time in minutes
        
    Returns:
        Encoded JWT token
    """
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(minutes=expires_minutes)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.now(timezone.utc),
        "type": "verification"
    })
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM
    )
    
    return encoded_jwt


def password_fingerprint(hashed_password: Optional[str]) -> str:
    """Short digest of the stored hash. A reset token carries it, so the token dies with the
    password it was issued for: one use, no table to keep."""
    return hashlib.sha256((hashed_password or "").encode("utf-8")).hexdigest()[:16]


def decode_verification_payload(token: str, purpose: str) -> Optional[Dict[str, Any]]:
    """Claims of a verification token of the given purpose, or None."""
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except jwt.PyJWTError:
        return None
    if payload.get("type") != "verification" or payload.get("purpose") != purpose:
        return None
    return payload


def decode_verification_token(token: str, purpose: str) -> Optional[str]:
    """
    Decode and verify a verification token.
    
    Args:
        token: JWT token string
        purpose: Expected purpose ("email_verify", "password_reset")
        
    Returns:
        User ID if valid, None otherwise
    """
    try:
        payload = jwt.decode(
            token,
            settings.SECRET_KEY,
            algorithms=[settings.ALGORITHM]
        )
        
        # Verify token type
        if payload.get("type") != "verification":
            return None
        
        # Verify purpose
        if payload.get("purpose") != purpose:
            return None
        
        return payload.get("sub")
    except jwt.PyJWTError:
        return None


async def verify_google_token(id_token: str, audience: str | None = None) -> Optional[Dict[str, Any]]:
    """
    Verify Google OAuth ID token.
    
    Args:
        id_token: Google ID token from client
        audience: Expected client ID (audience) to validate against
        
    Returns:
        User info dict with email, name, picture, or None if invalid
        
    Note:
        Requires google-auth library. Falls back to mock for development.
    """
    import logging
    logger = logging.getLogger(__name__)
    
    logger.info(f"verify_google_token called with audience={audience}")
    
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests
        
        # Verify the token
        idinfo = await anyio.to_thread.run_sync(
            lambda: google_id_token.verify_oauth2_token(
                id_token,
                requests.Request(),
                audience=audience,
            )
        )
        
        logger.info(f"Google token verified successfully for email={idinfo.get('email')}")
        
        return {
            "email": idinfo.get("email"),
            "name": idinfo.get("name"),
            "picture": idinfo.get("picture"),
            "google_id": idinfo.get("sub"),
            "email_verified": idinfo.get("email_verified", False)
        }
    except ImportError:
        logger.warning("google-auth not installed. Google OAuth will not work.")
        return None
    except ValueError as e:
        logger.error(f"Google token verification ValueError: {e}")
        logger.error(f"This usually means: token expired, wrong audience, or malformed token")
        return None
    except Exception as e:
        logger.error(f"Google token verification failed: {type(e).__name__}: {e}")
        return None
