"""
Tests for Authentication API Routes

Covers:
- POST /auth/register   — success (201), duplicate email/username (400), validation (422)
- POST /auth/login      — success, wrong password (401), user not found (401), inactive (403)
- POST /auth/refresh    — valid token, invalid token, wrong token type
- GET  /auth/me         — authenticated returns user
- POST /auth/logout     — success message
- POST /auth/forgot-password — always-success anti-enumeration response
- POST /auth/reset-password  — valid token, invalid token, weak password
- POST /auth/verify-email    — valid token, invalid token, already verified
- POST /auth/google          — invalid token, new user, link to unverified local account, blocked link
- POST /auth/facebook        — invalid token, success, inactive
- POST /auth/admin/login     — success, wrong role, unverified, inactive
- POST /auth/admin/request-otp, /auth/admin/verify-otp — anti-enumeration, unverified blocked, success
- POST /auth/change-password — success, wrong current password, OAuth-only blocked
- POST /auth/resend-verification — always-success anti-enumeration response
"""

import uuid
import pytest
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport


BASE = "/api/v1/auth"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_mock_user(
    *,
    is_active: bool = True,
    is_verified: bool = True,
    provider: tuple[str, ...] = ("local",),
    hashed_password: str = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
) -> MagicMock:
    """Build a minimal mock User ORM object."""
    u = MagicMock()
    u.id = uuid.UUID("550e8400-e29b-41d4-a716-446655440001")
    u.email = "test@example.com"
    u.username = "testuser"
    u.display_name = "Test User"
    u.hashed_password = hashed_password
    u.is_active = is_active
    u.is_verified = is_verified
    u.provider = list(provider)
    # MagicMock auto-generates truthy attributes for undefined properties, so
    # has_local_auth/has_google_auth must be set explicitly to mirror the real
    # User.has_local_auth/has_google_auth @property behavior based on provider.
    u.has_local_auth = "local" in u.provider
    u.has_google_auth = "google" in u.provider

    def _add_provider(p: str) -> None:
        if p not in u.provider:
            u.provider.append(p)
        if p == "google":
            u.has_google_auth = True
        elif p == "local":
            u.has_local_auth = True

    u.add_provider = MagicMock(side_effect=_add_provider)
    u.native_language = "vi"
    u.target_language = "en"
    u.level = "beginner"
    u.total_xp = 0
    u.numeric_level = 1
    u.rank = "bronze"
    u.role_slug = "user"
    u.role_level = 0
    u.is_admin = False
    u.is_super_admin = False
    u.role_id = None
    u.created_at = datetime.now(UTC)
    u.last_login = None
    u.avatar_url = None
    return u


def _make_mock_session(
    *,
    scalar_one_or_none_value=None,
    scalar_value=None,
    scalar_one_or_none_side_effect=None,
) -> MagicMock:
    """Create a mock AsyncSession with configurable return values."""
    mock_result = MagicMock()
    if scalar_one_or_none_side_effect is not None:
        mock_result.scalar_one_or_none.side_effect = scalar_one_or_none_side_effect
    else:
        mock_result.scalar_one_or_none.return_value = scalar_one_or_none_value
    mock_result.scalar.return_value = scalar_value
    mock_result.scalars.return_value.all.return_value = []
    mock_result.all.return_value = []

    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    async def fake_refresh(obj):
        if not getattr(obj, "id", None):
            obj.id = uuid.UUID("550e8400-e29b-41d4-a716-446655440002")
        if not getattr(obj, "created_at", None):
            obj.created_at = datetime.now(UTC)
        if getattr(obj, "is_active", None) is None:
            obj.is_active = True
        if getattr(obj, "is_verified", None) is None:
            obj.is_verified = False
        if getattr(obj, "native_language", None) is None:
            obj.native_language = "vi"
        if getattr(obj, "target_language", None) is None:
            obj.target_language = "en"
        if getattr(obj, "level", None) is None:
            obj.level = "beginner"
        if getattr(obj, "total_xp", None) is None:
            obj.total_xp = 0
        if getattr(obj, "numeric_level", None) is None:
            obj.numeric_level = 1
        if getattr(obj, "rank", None) is None:
            obj.rank = "bronze"
        # role_slug, role_level, is_admin, is_super_admin are @property on User ORM model
        # and return sensible defaults when role is None, so we don't set them here.

    mock_session.execute = fake_execute
    mock_session.add = MagicMock()
    mock_session.commit = AsyncMock()
    mock_session.flush = AsyncMock()
    mock_session.refresh = AsyncMock(side_effect=fake_refresh)
    return mock_session


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
async def client():
    """Unauthenticated client — DB always returns 'not found'."""
    from app.main import app
    from app.core.database import get_db

    session = _make_mock_session()

    async def mock_get_db():
        yield session

    app.dependency_overrides[get_db] = mock_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
async def auth_client():
    """Authenticated client — mocked user + DB returns not-found by default."""
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    session = _make_mock_session()
    mock_user = _make_mock_user()

    async def mock_get_db():
        yield session

    async def mock_get_current_user():
        return mock_user

    app.dependency_overrides[get_db] = mock_get_db
    app.dependency_overrides[get_current_user] = mock_get_current_user
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# Helper: build an inline client with custom DB behavior
# ---------------------------------------------------------------------------

async def _make_inline_client(scalar_one_or_none_value=None, scalar_one_or_none_side_effect=None):
    """Contextmanager-like helper — returns (app, transport) pair so tests can use it."""
    from app.main import app
    from app.core.database import get_db

    session = _make_mock_session(
        scalar_one_or_none_value=scalar_one_or_none_value,
        scalar_one_or_none_side_effect=scalar_one_or_none_side_effect,
    )

    async def mock_get_db():
        yield session

    app.dependency_overrides[get_db] = mock_get_db
    return app, session


# ===========================================================================
# POST /auth/register
# ===========================================================================

class TestRegister:

    async def test_register_success_returns_201(self, client):
        """Valid registration creates a user and returns 201."""
        with patch("app.routes.auth.EmailService.send_verification_email", new=AsyncMock()):
            response = await client.post(
                f"{BASE}/register",
                json={
                    "email": "newuser@example.com",
                    "username": "newuser",
                    "password": "SecurePass123!",
                },
            )
        assert response.status_code == 201

    async def test_register_success_response_has_email(self, client):
        """Successful register response includes submitted email."""
        with patch("app.routes.auth.EmailService.send_verification_email", new=AsyncMock()):
            response = await client.post(
                f"{BASE}/register",
                json={
                    "email": "another@example.com",
                    "username": "anotheruser",
                    "password": "SecurePass123!",
                },
            )
        assert response.status_code == 201
        data = response.json()
        assert data["email"] == "another@example.com"
        assert data["username"] == "anotheruser"

    async def test_register_duplicate_email_returns_400(self):
        """Registration with an already-used email returns 400."""
        from app.main import app
        from app.core.database import get_db

        existing_user = _make_mock_user()
        session = _make_mock_session(scalar_one_or_none_value=existing_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(
                f"{BASE}/register",
                json={
                    "email": "test@example.com",
                    "username": "newuser",
                    "password": "SecurePass123!",
                },
            )
        app.dependency_overrides.clear()

        assert response.status_code == 400
        assert "Email already registered" in response.json()["error"]["message"]

    async def test_register_duplicate_username_returns_400(self):
        """Registration with an already-taken username returns 400."""
        from app.main import app
        from app.core.database import get_db

        existing_user = _make_mock_user()
        # First call (email check) → None; second call (username check) → existing_user
        side_effects = [None, existing_user]
        call_idx = [0]

        def get_side():
            val = side_effects[min(call_idx[0], len(side_effects) - 1)]
            call_idx[0] += 1
            return val

        session = _make_mock_session(scalar_one_or_none_side_effect=get_side)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(
                f"{BASE}/register",
                json={
                    "email": "unique@example.com",
                    "username": "testuser",
                    "password": "SecurePass123!",
                },
            )
        app.dependency_overrides.clear()

        assert response.status_code == 400
        assert "Username already taken" in response.json()["error"]["message"]

    async def test_register_invalid_email_returns_422(self, client):
        """Invalid email format triggers 422 validation error."""
        response = await client.post(
            f"{BASE}/register",
            json={
                "email": "not-a-valid-email",
                "username": "validuser",
                "password": "SecurePass123!",
            },
        )
        assert response.status_code == 422

    async def test_register_password_too_short_returns_422(self, client):
        """Password shorter than 8 chars triggers 422 validation error."""
        response = await client.post(
            f"{BASE}/register",
            json={
                "email": "valid@example.com",
                "username": "validuser",
                "password": "short",
            },
        )
        assert response.status_code == 422

    async def test_register_missing_email_returns_422(self, client):
        """Missing required email field triggers 422."""
        response = await client.post(
            f"{BASE}/register",
            json={"username": "validuser", "password": "SecurePass123!"},
        )
        assert response.status_code == 422


# ===========================================================================
# POST /auth/login
# ===========================================================================

class TestLogin:

    async def test_login_user_not_found_returns_401(self, client):
        """Login with unknown email returns 401."""
        response = await client.post(
            f"{BASE}/login",
            json={"email": "ghost@example.com", "password": "testpass"},
        )
        assert response.status_code == 401
        assert "Incorrect email or password" in response.json()["error"]["message"]

    async def test_login_wrong_password_returns_401(self):
        """Login with wrong password returns 401."""
        from app.main import app
        from app.core.database import get_db

        mock_login_user = _make_mock_user()
        session = _make_mock_session(scalar_one_or_none_value=mock_login_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.services.auth_service.verify_password_async", new=AsyncMock(return_value=False)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/login",
                    json={"email": "test@example.com", "password": "wrongpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 401
        assert "Incorrect email or password" in response.json()["error"]["message"]

    async def test_login_success_returns_200_with_tokens(self):
        """Valid credentials return 200 with access_token and refresh_token."""
        from app.main import app
        from app.core.database import get_db

        mock_login_user = _make_mock_user()
        session = _make_mock_session(scalar_one_or_none_value=mock_login_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.services.auth_service.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/login",
                    json={"email": "test@example.com", "password": "testpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data
        assert data["token_type"] == "bearer"

    async def test_login_inactive_user_returns_403(self):
        """Login attempt with inactive account returns 403."""
        from app.main import app
        from app.core.database import get_db

        inactive_user = _make_mock_user(is_active=False)
        session = _make_mock_session(scalar_one_or_none_value=inactive_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.services.auth_service.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/login",
                    json={"email": "test@example.com", "password": "testpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 403
        assert "inactive" in response.json()["error"]["message"].lower()

    async def test_login_missing_password_returns_422(self, client):
        """Missing password field triggers 422 validation error."""
        response = await client.post(
            f"{BASE}/login",
            json={"email": "test@example.com"},
        )
        assert response.status_code == 422

    async def test_login_unverified_user_returns_403(self):
        """Correct credentials but unverified email returns 403, not tokens."""
        from app.main import app
        from app.core.database import get_db

        unverified_user = _make_mock_user(is_verified=False)
        session = _make_mock_session(scalar_one_or_none_value=unverified_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.services.auth_service.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/login",
                    json={"email": "test@example.com", "password": "testpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 403
        message = response.json()["error"]["message"].lower()
        assert "not verified" in message
        data = response.json()
        assert "access_token" not in data
        assert "refresh_token" not in data


# ===========================================================================
# POST /auth/refresh
# ===========================================================================

class TestRefreshToken:

    async def test_refresh_invalid_token_returns_401(self, client):
        """An unparseable refresh token returns 401."""
        with patch("app.core.security.decode_token", return_value=None):
            response = await client.post(
                f"{BASE}/refresh",
                json={"refresh_token": "completely.invalid.token"},
            )
        assert response.status_code == 401
        assert "Invalid refresh token" in response.json()["error"]["message"]

    async def test_refresh_wrong_token_type_returns_401(self, client):
        """An access token (type='access') used as refresh token returns 401."""
        with patch(
            "app.core.security.decode_token",
            return_value={"type": "access", "sub": "some-user-id"},
        ):
            response = await client.post(
                f"{BASE}/refresh",
                json={"refresh_token": "access.token.here"},
            )
        assert response.status_code == 401
        assert "Invalid token type" in response.json()["error"]["message"]

    async def test_refresh_valid_token_returns_new_tokens(self):
        """Valid refresh token returns new access_token + refresh_token."""
        from app.main import app
        from app.core.database import get_db

        mock_login_user = _make_mock_user()
        session = _make_mock_session(scalar_one_or_none_value=mock_login_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch(
            "app.core.security.decode_token",
            return_value={"type": "refresh", "sub": "00000000-0000-0000-0000-000000000001"},
        ):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/refresh",
                    json={"refresh_token": "valid.refresh.token"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert "refresh_token" in data

    async def test_refresh_user_not_found_returns_401(self, client):
        """Valid token structure but no matching DB user returns 401."""
        with patch(
            "app.core.security.decode_token",
            return_value={"type": "refresh", "sub": "00000000-0000-0000-0000-000000000099"},
        ):
            response = await client.post(
                f"{BASE}/refresh",
                json={"refresh_token": "valid.refresh.token"},
            )
        assert response.status_code == 401

    async def test_refresh_unverified_user_returns_403(self):
        """A still-unverified user cannot use a refresh token to renew access either."""
        from app.main import app
        from app.core.database import get_db

        unverified_user = _make_mock_user(is_verified=False)
        session = _make_mock_session(scalar_one_or_none_value=unverified_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch(
            "app.core.security.decode_token",
            return_value={"type": "refresh", "sub": "00000000-0000-0000-0000-000000000001"},
        ):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/refresh",
                    json={"refresh_token": "valid.refresh.token"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 403
        message = response.json()["error"]["message"].lower()
        assert "not verified" in message


# ===========================================================================
# GET /auth/me
# ===========================================================================

class TestGetMe:

    async def test_get_me_authenticated_returns_200(self, auth_client):
        """Authenticated request to /me returns 200 with user data."""
        response = await auth_client.get(f"{BASE}/me")
        assert response.status_code == 200

    async def test_get_me_has_email_and_username(self, auth_client):
        """Response includes email and username fields."""
        response = await auth_client.get(f"{BASE}/me")
        data = response.json()
        assert "email" in data
        assert "username" in data


# ===========================================================================
# POST /auth/logout
# ===========================================================================

class TestLogout:

    async def test_logout_returns_200(self, client):
        """Logout endpoint always returns 200."""
        response = await client.post(f"{BASE}/logout", json={})
        assert response.status_code == 200

    async def test_logout_response_has_message(self, client):
        """Logout response contains a 'message' field."""
        response = await client.post(f"{BASE}/logout", json={})
        data = response.json()
        assert "message" in data
        assert "Logged out" in data["message"]


# ===========================================================================
# POST /auth/forgot-password
# ===========================================================================

class TestForgotPassword:

    async def test_forgot_password_nonexistent_email_still_200(self, client):
        """Forgot password with unknown email returns 200 (anti-enumeration)."""
        response = await client.post(
            f"{BASE}/forgot-password",
            json={"email": "nobody@example.com"},
        )
        assert response.status_code == 200

    async def test_forgot_password_response_has_message(self, client):
        """Response always contains a 'message' field."""
        response = await client.post(
            f"{BASE}/forgot-password",
            json={"email": "nobody@example.com"},
        )
        data = response.json()
        assert "message" in data

    async def test_forgot_password_existing_user_returns_200(self):
        """Forgot password for a real email returns 200."""
        from app.main import app
        from app.core.database import get_db

        existing_user = _make_mock_user()
        session = _make_mock_session(scalar_one_or_none_value=existing_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.core.security.create_verification_token", return_value="fake-token"), \
             patch("app.routes.auth.EmailService.send_password_reset_email", new=AsyncMock()):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/forgot-password",
                    json={"email": "test@example.com"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200

    async def test_forgot_password_invalid_email_returns_422(self, client):
        """Non-email value triggers 422 validation error."""
        response = await client.post(
            f"{BASE}/forgot-password",
            json={"email": "not-an-email"},
        )
        assert response.status_code == 422


# ===========================================================================
# POST /auth/reset-password
# ===========================================================================

class TestResetPassword:

    async def test_reset_password_invalid_token_returns_400(self, client):
        """An invalid/expired reset token returns 400."""
        with patch("app.core.security.decode_verification_token", return_value=None):
            response = await client.post(
                f"{BASE}/reset-password",
                json={"token": "bad-token", "new_password": "newpassword123"},
            )
        assert response.status_code == 400
        assert "Invalid or expired reset token" in response.json()["error"]["message"]

    async def test_reset_password_valid_token_returns_200(self):
        """Valid reset token + new password returns 200."""
        from app.main import app
        from app.core.database import get_db

        user = _make_mock_user()
        session = _make_mock_session(scalar_one_or_none_value=user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        user_id = str(user.id)
        with patch("app.core.security.decode_verification_token", return_value=user_id):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/reset-password",
                    json={"token": "valid-token", "new_password": "newpassword123"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert "Password reset successfully" in data["message"]

    async def test_reset_password_too_short_returns_422(self, client):
        """New password shorter than 8 chars triggers 422."""
        response = await client.post(
            f"{BASE}/reset-password",
            json={"token": "some-token", "new_password": "short"},
        )
        assert response.status_code == 422


# ===========================================================================
# POST /auth/verify-email
# ===========================================================================

class TestVerifyEmail:

    async def test_verify_email_invalid_token_returns_400(self, client):
        """An invalid/expired verification token returns 400."""
        with patch("app.core.security.decode_verification_token", return_value=None):
            response = await client.post(
                f"{BASE}/verify-email",
                json={"token": "bad-verification-token"},
            )
        assert response.status_code == 400
        assert "Invalid or expired verification token" in response.json()["error"]["message"]

    async def test_verify_email_valid_token_unverified_user_returns_200(self):
        """Valid token for an unverified user returns verified=True."""
        from app.main import app
        from app.core.database import get_db

        user = _make_mock_user(is_verified=False)
        session = _make_mock_session(scalar_one_or_none_value=user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        user_id = str(user.id)
        with patch("app.core.security.decode_verification_token", return_value=user_id):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/verify-email",
                    json={"token": "valid-verify-token"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert data["verified"] is True

    async def test_verify_email_already_verified_user_returns_200(self):
        """Already-verified user returns verified=True with appropriate message."""
        from app.main import app
        from app.core.database import get_db

        user = _make_mock_user(is_verified=True)
        session = _make_mock_session(scalar_one_or_none_value=user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        user_id = str(user.id)
        with patch("app.core.security.decode_verification_token", return_value=user_id):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/verify-email",
                    json={"token": "valid-verify-token"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert data["verified"] is True
        assert "already verified" in data["message"].lower()


# ===========================================================================
# POST /auth/google
# ===========================================================================

class TestGoogleLogin:

    async def test_google_login_invalid_token_returns_401(self, client):
        """An unverifiable Google ID token returns 401."""
        with patch("app.core.security.verify_google_token", new=AsyncMock(return_value=None)), \
             patch("app.core.firebase_auth.verify_firebase_token", return_value=None):
            response = await client.post(
                f"{BASE}/google",
                json={"id_token": "bad-token", "source": "app"},
            )
        assert response.status_code == 401

    async def test_google_login_new_user_created_returns_200(self):
        """A first-time Google sign-in (email_verified=True) creates a new user."""
        from app.main import app
        from app.core.database import get_db

        session = _make_mock_session(scalar_one_or_none_value=None)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        google_info = {"email": "newgoogle@example.com", "email_verified": True, "name": "New Google User"}
        with patch("app.core.security.verify_google_token", new=AsyncMock(return_value=google_info)), \
             patch("app.routes.auth._ensure_unique_username", new=AsyncMock(return_value="newgoogleuser")), \
             patch("app.routes.auth._get_role_id", new=AsyncMock(return_value=None)), \
             patch(
                 "app.services.starter_reward_service.StarterRewardService.grant_new_user_reward",
                 new=AsyncMock(),
             ):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/google",
                    json={"id_token": "good-token", "source": "app"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data

    async def test_google_login_links_unverified_local_account_when_email_verified(self):
        """Google vouching for the email (email_verified=True) verifies and links
        an existing unverified local-only account instead of blocking it (Phase 2.2)."""
        from app.main import app
        from app.core.database import get_db

        local_user = _make_mock_user(is_verified=False, provider=["local"])
        session = _make_mock_session(scalar_one_or_none_value=local_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        google_info = {"email": "test@example.com", "email_verified": True, "name": "Test User"}
        with patch("app.core.security.verify_google_token", new=AsyncMock(return_value=google_info)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/google",
                    json={"id_token": "good-token", "source": "app"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert local_user.is_verified is True
        assert "google" in local_user.provider

    async def test_google_login_local_account_blocked_when_email_not_verified(self):
        """If Google has NOT verified the email, an unverified local account stays blocked."""
        from app.main import app
        from app.core.database import get_db

        local_user = _make_mock_user(is_verified=False, provider=["local"])
        session = _make_mock_session(scalar_one_or_none_value=local_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        google_info = {"email": "test@example.com", "email_verified": False, "name": "Test User"}
        with patch("app.core.security.verify_google_token", new=AsyncMock(return_value=google_info)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/google",
                    json={"id_token": "good-token", "source": "app"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 400

    async def test_google_login_admin_source_not_allowlisted_new_user_returns_403(self):
        """Admin-source Google login for a brand-new, non-allowlisted email is rejected."""
        from app.main import app
        from app.core.database import get_db

        session = _make_mock_session(scalar_one_or_none_value=None)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        google_info = {"email": "stranger@example.com", "email_verified": True, "name": "Stranger"}
        with patch("app.core.security.verify_google_token", new=AsyncMock(return_value=google_info)), \
             patch("app.core.config.settings.GOOGLE_ADMIN_CLIENT_ID", "admin-client-id"), \
             patch("app.core.config.Settings.get_admin_role_for_email", return_value=None):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/google",
                    json={"id_token": "good-token", "source": "admin"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 403


# ===========================================================================
# POST /auth/facebook
# ===========================================================================

class TestFacebookLogin:

    async def test_facebook_login_invalid_token_returns_401(self, client):
        """An unverifiable Firebase ID token returns 401."""
        with patch("app.core.firebase_auth.verify_firebase_token", return_value=None):
            response = await client.post(
                f"{BASE}/facebook",
                json={"id_token": "bad-token", "source": "app"},
            )
        assert response.status_code == 401

    async def test_facebook_login_success_returns_200(self, client):
        """A valid Facebook (Firebase) token returns tokens for an active user."""
        fb_user = _make_mock_user(is_active=True)
        claims = {
            "email": fb_user.email,
            "email_verified": True,
            "firebase": {"sign_in_provider": "facebook.com"},
        }
        with patch("app.core.firebase_auth.verify_firebase_token", return_value=claims), \
             patch("app.core.firebase_auth.get_or_create_user_from_claims", new=AsyncMock(return_value=fb_user)):
            response = await client.post(
                f"{BASE}/facebook",
                json={"id_token": "good-token", "source": "app"},
            )
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data

    async def test_facebook_login_inactive_user_returns_403(self, client):
        """An inactive account cannot complete Facebook login."""
        fb_user = _make_mock_user(is_active=False)
        claims = {
            "email": fb_user.email,
            "email_verified": True,
            "firebase": {"sign_in_provider": "facebook.com"},
        }
        with patch("app.core.firebase_auth.verify_firebase_token", return_value=claims), \
             patch("app.core.firebase_auth.get_or_create_user_from_claims", new=AsyncMock(return_value=fb_user)):
            response = await client.post(
                f"{BASE}/facebook",
                json={"id_token": "good-token", "source": "app"},
            )
        assert response.status_code == 403


# ===========================================================================
# POST /auth/admin/login
# ===========================================================================

class TestAdminLogin:

    def _admin_user(self, *, is_active=True, is_verified=True, role_level=1):
        user = _make_mock_user(is_active=is_active, is_verified=is_verified)
        user.role_level = role_level
        return user

    async def test_admin_login_success_returns_200_with_tokens(self):
        from app.main import app
        from app.core.database import get_db

        admin_user = self._admin_user()
        session = _make_mock_session(scalar_one_or_none_value=admin_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/admin/login",
                    json={"email": "admin@example.com", "password": "testpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        assert "access_token" in response.json()["data"]

    async def test_admin_login_insufficient_role_returns_403(self):
        from app.main import app
        from app.core.database import get_db

        regular_user = self._admin_user(role_level=0)
        session = _make_mock_session(scalar_one_or_none_value=regular_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/admin/login",
                    json={"email": "user@example.com", "password": "testpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 403
        assert "Admin privileges" in response.json()["error"]["message"]

    async def test_admin_login_unverified_returns_403(self):
        """An admin account that hasn't verified its email cannot log in (Phase 2.1)."""
        from app.main import app
        from app.core.database import get_db

        admin_user = self._admin_user(is_verified=False)
        session = _make_mock_session(scalar_one_or_none_value=admin_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/admin/login",
                    json={"email": "admin@example.com", "password": "testpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 403
        assert "not verified" in response.json()["error"]["message"].lower()

    async def test_admin_login_inactive_returns_403(self):
        from app.main import app
        from app.core.database import get_db

        admin_user = self._admin_user(is_active=False)
        session = _make_mock_session(scalar_one_or_none_value=admin_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/admin/login",
                    json={"email": "admin@example.com", "password": "testpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 403
        assert "inactive" in response.json()["error"]["message"].lower()

    async def test_admin_login_wrong_password_returns_401(self):
        from app.main import app
        from app.core.database import get_db

        admin_user = self._admin_user()
        session = _make_mock_session(scalar_one_or_none_value=admin_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=False)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/admin/login",
                    json={"email": "admin@example.com", "password": "wrongpass"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 401


# ===========================================================================
# POST /auth/admin/request-otp, /auth/admin/verify-otp
# ===========================================================================

class TestAdminOtp:

    async def test_request_otp_unknown_email_still_200(self, client):
        """Anti-enumeration: unknown email returns 200 same as a real admin."""
        response = await client.post(
            f"{BASE}/admin/request-otp",
            json={"email": "ghost@example.com"},
        )
        assert response.status_code == 200

    async def test_request_otp_unverified_admin_still_200_but_no_otp_sent(self):
        """An unverified admin gets the same generic 200 response (Phase 2.1), but no
        OTP is actually generated for them — verified implicitly via verify-otp failing."""
        from app.main import app
        from app.core.database import get_db
        from app.routes import auth as auth_routes

        unverified_admin = _make_mock_user(is_verified=False)
        unverified_admin.role_level = 1
        session = _make_mock_session(scalar_one_or_none_value=unverified_admin)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        auth_routes._admin_otp_store.clear()
        transport = ASGITransport(app=app)

        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(
                f"{BASE}/admin/request-otp",
                json={"email": unverified_admin.email},
            )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        assert unverified_admin.email not in auth_routes._admin_otp_store

    async def test_verify_otp_invalid_code_returns_400(self, client):
        response = await client.post(
            f"{BASE}/admin/verify-otp",
            json={"email": "admin@example.com", "otp": "000000"},
        )
        assert response.status_code == 400

    async def test_verify_otp_unverified_admin_returns_403(self):
        """A valid OTP cannot bypass the is_verified check on verify-otp (Phase 2.1)."""
        from app.main import app
        from app.core.database import get_db
        from app.routes import auth as auth_routes
        import time

        unverified_admin = _make_mock_user(is_verified=False)
        unverified_admin.role_level = 1
        session = _make_mock_session(scalar_one_or_none_value=unverified_admin)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        auth_routes._admin_otp_store[unverified_admin.email] = ("123456", time.time() + 300)
        transport = ASGITransport(app=app)

        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(
                f"{BASE}/admin/verify-otp",
                json={"email": unverified_admin.email, "otp": "123456"},
            )
        app.dependency_overrides.clear()

        assert response.status_code == 403

    async def test_verify_otp_success_returns_tokens(self):
        from app.main import app
        from app.core.database import get_db
        from app.routes import auth as auth_routes
        import time

        admin_user = _make_mock_user(is_verified=True)
        admin_user.role_level = 1
        session = _make_mock_session(scalar_one_or_none_value=admin_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        auth_routes._admin_otp_store[admin_user.email] = ("654321", time.time() + 300)
        transport = ASGITransport(app=app)

        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(
                f"{BASE}/admin/verify-otp",
                json={"email": admin_user.email, "otp": "654321"},
            )
        app.dependency_overrides.clear()

        assert response.status_code == 200
        assert "access_token" in response.json()["data"]


# ===========================================================================
# POST /auth/change-password
# ===========================================================================

class TestChangePassword:

    async def test_change_password_success_returns_200(self, auth_client):
        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=True)):
            response = await auth_client.post(
                f"{BASE}/change-password",
                json={"current_password": "oldpass123", "new_password": "newpass456"},
            )
        assert response.status_code == 200

    async def test_change_password_wrong_current_password_returns_400(self, auth_client):
        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=False)):
            response = await auth_client.post(
                f"{BASE}/change-password",
                json={"current_password": "wrongpass", "new_password": "newpass456"},
            )
        assert response.status_code == 400
        assert "incorrect" in response.json()["error"]["message"].lower()

    async def test_change_password_oauth_only_account_returns_400(self):
        """An OAuth-only account (no 'local' provider) cannot change a password it doesn't have."""
        from app.main import app
        from app.core.database import get_db
        from app.core.dependencies import get_current_user

        oauth_user = _make_mock_user(provider=["google"])
        session = _make_mock_session()

        async def mock_get_db():
            yield session

        async def mock_get_current_user():
            return oauth_user

        app.dependency_overrides[get_db] = mock_get_db
        app.dependency_overrides[get_current_user] = mock_get_current_user
        transport = ASGITransport(app=app)

        with patch("app.routes.auth.verify_password_async", new=AsyncMock(return_value=True)):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/change-password",
                    json={"current_password": "whatever", "new_password": "newpass456"},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 400
        assert "OAuth" in response.json()["error"]["message"]


# ===========================================================================
# POST /auth/resend-verification
# ===========================================================================

class TestResendVerification:

    async def test_resend_verification_unknown_email_still_200(self, client):
        """Anti-enumeration: unknown email returns the same generic 200."""
        response = await client.post(
            f"{BASE}/resend-verification",
            json={"email": "ghost@example.com"},
        )
        assert response.status_code == 200

    async def test_resend_verification_unverified_user_returns_200(self):
        from app.main import app
        from app.core.database import get_db

        unverified_user = _make_mock_user(is_verified=False)
        session = _make_mock_session(scalar_one_or_none_value=unverified_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        with patch("app.core.security.create_verification_token", return_value="fake-token"), \
             patch("app.services.email_service.EmailService.send_verification_email", new=AsyncMock()):
            async with AsyncClient(transport=transport, base_url="http://test") as c:
                response = await c.post(
                    f"{BASE}/resend-verification",
                    json={"email": unverified_user.email},
                )
        app.dependency_overrides.clear()

        assert response.status_code == 200

    async def test_resend_verification_already_verified_user_returns_200(self):
        """Already-verified users get the same generic response (no email sent)."""
        from app.main import app
        from app.core.database import get_db

        verified_user = _make_mock_user(is_verified=True)
        session = _make_mock_session(scalar_one_or_none_value=verified_user)

        async def mock_get_db():
            yield session

        app.dependency_overrides[get_db] = mock_get_db
        transport = ASGITransport(app=app)

        async with AsyncClient(transport=transport, base_url="http://test") as c:
            response = await c.post(
                f"{BASE}/resend-verification",
                json={"email": verified_user.email},
            )
        app.dependency_overrides.clear()

        assert response.status_code == 200
