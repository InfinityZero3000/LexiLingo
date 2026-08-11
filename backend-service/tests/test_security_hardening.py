"""
Hardening tests for project security changes.
"""

import pytest
import html
from typing import AsyncGenerator
from httpx import AsyncClient, ASGITransport
from app.main import app
from app.core.security import create_verification_token, decode_verification_token
from app.services.email_service import EmailService


@pytest.fixture
async def async_client_no_db() -> AsyncGenerator[AsyncClient, None]:
    """Create async HTTP client without database dependencies."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client


@pytest.mark.asyncio
async def test_security_headers_middleware(async_client_no_db: AsyncClient):
    """
    Test that the SecurityHeadersMiddleware successfully sets all target
    security headers on HTTP responses.
    """
    response = await async_client_no_db.get("/")
    assert response.status_code == 200
    
    # Assert defense-in-depth headers are present and correctly set
    assert response.headers.get("X-Content-Type-Options") == "nosniff"
    assert response.headers.get("X-Frame-Options") == "DENY"
    assert response.headers.get("X-XSS-Protection") == "1; mode=block"
    assert response.headers.get("Referrer-Policy") == "strict-origin-when-cross-origin"
    assert "default-src 'self'" in response.headers.get("Content-Security-Policy", "")
    assert "camera=()" in response.headers.get("Permissions-Policy", "")


@pytest.mark.asyncio
async def test_email_verification_token_flow():
    """
    Verify that verification token creation and decoding are consistent
    and work correctly after changing the payload key to 'purpose'.
    """
    user_id = "00000000-0000-0000-0000-000000000001"
    email = "test@example.com"
    
    # Create the verification token using the updated payload parameters
    token = create_verification_token(
        {"sub": user_id, "email": email, "purpose": "email_verify"},
        expires_minutes=1440
    )
    
    # Decode the token and verify it decodes successfully
    decoded_user_id = decode_verification_token(token, "email_verify")
    assert decoded_user_id == user_id
    
    # Decode with a different purpose should fail
    assert decode_verification_token(token, "password_reset") is None


def test_email_html_escaping():
    """
    Verify that user inputs like display_name are HTML-escaped in email messages
    to prevent HTML injection.
    """
    malicious_display_name = "<script>alert(1)</script> & Hello"
    otp = "123456"
    
    msg = EmailService._build_otp_message(
        to_email="test@example.com",
        otp=otp,
        display_name=malicious_display_name
    )
    
    # Extract alternative HTML parts
    html_part = None
    for part in msg.walk():
        if part.get_content_type() == "text/html":
            html_part = part.get_content()
            break
            
    assert html_part is not None
    # The display name must be escaped: '<' -> '&lt;', '>' -> '&gt;', '&' -> '&amp;'
    escaped_display_name = html.escape(malicious_display_name)
    assert escaped_display_name in html_part
    assert malicious_display_name not in html_part
