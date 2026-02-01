"""
Security utilities

JWT token creation/validation and password hashing
"""

from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from jose import JWTError, jwt
import bcrypt

from app.core.config import settings


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify plain password against hashed password."""
    return bcrypt.checkpw(
        plain_password.encode('utf-8'),
        hashed_password.encode('utf-8')
    )


def get_password_hash(password: str) -> str:
    """Hash a password."""
    return bcrypt.hashpw(
        password.encode('utf-8'),
        bcrypt.gensalt()
    ).decode('utf-8')


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
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow(),
        "type": "access"  # Token type marker
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
    expire = datetime.utcnow() + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow(),
        "type": "refresh"  # Token type marker
    })
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM
    )
    
    return encoded_jwt


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
            algorithms=[settings.ALGORITHM]
        )
        return payload
    except JWTError:
        return None


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
    expire = datetime.utcnow() + timedelta(minutes=expires_minutes)
    
    to_encode.update({
        "exp": expire,
        "iat": datetime.utcnow(),
        "type": "verification"
    })
    
    encoded_jwt = jwt.encode(
        to_encode,
        settings.SECRET_KEY,
        algorithm=settings.ALGORITHM
    )
    
    return encoded_jwt


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
    except JWTError:
        return None


async def verify_google_token(id_token: str) -> Optional[Dict[str, Any]]:
    """
    Verify Google OAuth ID token.
    
    Args:
        id_token: Google ID token from client
        
    Returns:
        User info dict with email, name, picture, or None if invalid
        
    Note:
        Requires google-auth library. Falls back to mock for development.
    """
    try:
        from google.oauth2 import id_token as google_id_token
        from google.auth.transport import requests
        
        # Verify the token
        idinfo = google_id_token.verify_oauth2_token(
            id_token,
            requests.Request(),
            audience=settings.GOOGLE_CLIENT_ID if hasattr(settings, 'GOOGLE_CLIENT_ID') else None
        )
        
        return {
            "email": idinfo.get("email"),
            "name": idinfo.get("name"),
            "picture": idinfo.get("picture"),
            "google_id": idinfo.get("sub"),
            "email_verified": idinfo.get("email_verified", False)
        }
    except ImportError:
        # google-auth not installed, log warning
        import logging
        logging.warning("google-auth not installed. Google OAuth will not work.")
        return None
    except Exception as e:
        import logging
        logging.error(f"Google token verification failed: {e}")
        return None

