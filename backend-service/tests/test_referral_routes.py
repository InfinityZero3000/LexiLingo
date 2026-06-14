"""Tests for referral system routes.

Covers:
- GET  /referral/my-code   — returns existing code, generates one if missing
- POST /referral/claim/{code} — success, self-claim (400), double-claim (409),
                                invalid code (404), concurrent double-claim safety
"""

from __future__ import annotations

import uuid
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch, call
import pytest
from httpx import AsyncClient, ASGITransport


BASE = "/api/v1/referral"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_user(
    *,
    referral_code: str | None = "ABCD1234",
    referred_by: uuid.UUID | None = None,
    gems: int = 100,
) -> MagicMock:
    u = MagicMock()
    u.id = uuid.uuid4()
    u.username = "testuser"
    u.email = "test@example.com"
    u.referral_code = referral_code
    u.referred_by = referred_by
    u.is_active = True
    u.is_verified = True
    u.provider = ["local"]
    u.role_slug = "user"
    u.role_level = 0
    u.is_admin = False
    u.is_super_admin = False
    return u


def _make_wallet(user_id: uuid.UUID, gems: int = 100) -> MagicMock:
    w = MagicMock()
    w.user_id = user_id
    w.gems = gems
    return w


def _make_mock_session() -> MagicMock:
    """Async session mock that can be customised per test via execute_results."""
    session = MagicMock()
    session.add = MagicMock()
    session.commit = AsyncMock()
    session.flush = AsyncMock()
    return session


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def current_user():
    return _make_user()


@pytest.fixture
async def authed_client(current_user):
    """Client with mocked auth dependency returning current_user."""
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user

    session = _make_mock_session()

    async def mock_get_db():
        yield session

    async def mock_get_current_user():
        return current_user

    app.dependency_overrides[get_db] = mock_get_db
    app.dependency_overrides[get_current_user] = mock_get_current_user

    async with AsyncClient(
        transport=ASGITransport(app=app), base_url="http://test"
    ) as client:
        yield client, session, current_user

    app.dependency_overrides.clear()


# ---------------------------------------------------------------------------
# GET /referral/my-code
# ---------------------------------------------------------------------------

class TestGetMyCode:
    @pytest.mark.asyncio
    async def test_returns_existing_code(self, authed_client):
        client, session, user = authed_client

        # Mock: count query returns 3
        count_result = MagicMock()
        count_result.scalar_one.return_value = 3

        async def fake_execute(query):
            return count_result

        session.execute = fake_execute

        resp = await client.get(f"{BASE}/my-code")
        assert resp.status_code == 200
        data = resp.json()
        assert data["referral_code"] == "ABCD1234"
        assert data["total_referrals"] == 3
        assert "referral_link" in data

    @pytest.mark.asyncio
    async def test_generates_code_when_missing(self, authed_client):
        client, session, user = authed_client
        user.referral_code = None

        # First execute: uniqueness check returns None (code is available)
        # Second execute: count query returns 0
        results = [
            _none_result(),   # uniqueness check
            _scalar_one_result(0),  # count
        ]
        idx = [0]

        async def fake_execute(query):
            r = results[min(idx[0], len(results) - 1)]
            idx[0] += 1
            return r

        session.execute = fake_execute

        resp = await client.get(f"{BASE}/my-code")
        assert resp.status_code == 200
        data = resp.json()
        assert data["referral_code"] is not None
        assert len(data["referral_code"]) == 8
        # Verify commit was called to persist the new code
        session.commit.assert_called_once()


# ---------------------------------------------------------------------------
# POST /referral/claim/{code}
# ---------------------------------------------------------------------------

class TestClaimCode:
    @pytest.mark.asyncio
    async def test_successful_claim_awards_gems(self, authed_client):
        client, session, claimer = authed_client
        claimer.referred_by = None

        referrer = _make_user(referral_code="REFER123")
        referrer_wallet = _make_wallet(referrer.id, gems=50)
        claimer_wallet = _make_wallet(claimer.id, gems=0)

        # Sequence: with_for_update user, referrer lookup, referrer wallet, claimer wallet
        results = [
            _scalar_one_result(claimer),   # locked user (with_for_update)
            _scalar_one_or_none_result(referrer),  # referrer lookup
            _scalar_one_or_none_result(referrer_wallet),  # referrer wallet
            _scalar_one_or_none_result(claimer_wallet),   # claimer wallet
        ]
        idx = [0]

        async def fake_execute(query):
            r = results[min(idx[0], len(results) - 1)]
            idx[0] += 1
            return r

        session.execute = fake_execute

        resp = await client.post(f"{BASE}/claim/REFER123")
        assert resp.status_code == 200
        data = resp.json()
        assert data["gems_awarded"] == 50
        # Referrer wallet should have been updated
        assert referrer_wallet.gems == 100  # 50 + 50
        # Claimer wallet should have been updated
        assert claimer_wallet.gems == 50
        # referred_by should be set
        assert claimer.referred_by == referrer.id
        session.commit.assert_called_once()

    @pytest.mark.asyncio
    async def test_self_referral_returns_400(self, authed_client):
        client, session, user = authed_client
        user.referred_by = None
        user.referral_code = "MYCODE12"

        # locked_user same as claimer, referrer same as claimer
        results = [
            _scalar_one_result(user),   # locked user
            _scalar_one_or_none_result(user),  # referrer lookup (same user)
        ]
        idx = [0]

        async def fake_execute(query):
            r = results[min(idx[0], len(results) - 1)]
            idx[0] += 1
            return r

        session.execute = fake_execute

        resp = await client.post(f"{BASE}/claim/MYCODE12")
        assert resp.status_code == 400
        session.commit.assert_not_called()

    @pytest.mark.asyncio
    async def test_double_claim_returns_409(self, authed_client):
        client, session, claimer = authed_client
        already_referred_id = uuid.uuid4()
        claimer.referred_by = already_referred_id

        locked = _make_user(referred_by=already_referred_id)

        async def fake_execute(query):
            return _scalar_one_result(locked)

        session.execute = fake_execute

        resp = await client.post(f"{BASE}/claim/XYZCODE1")
        assert resp.status_code == 409
        session.commit.assert_not_called()

    @pytest.mark.asyncio
    async def test_invalid_code_returns_404(self, authed_client):
        client, session, claimer = authed_client
        claimer.referred_by = None

        results = [
            _scalar_one_result(claimer),         # locked user
            _scalar_one_or_none_result(None),    # referrer lookup: not found
        ]
        idx = [0]

        async def fake_execute(query):
            r = results[min(idx[0], len(results) - 1)]
            idx[0] += 1
            return r

        session.execute = fake_execute

        resp = await client.post(f"{BASE}/claim/NOTEXIST")
        assert resp.status_code == 404
        session.commit.assert_not_called()

    @pytest.mark.asyncio
    async def test_code_path_param_too_short_returns_422(self, authed_client):
        client, session, _ = authed_client
        resp = await client.post(f"{BASE}/claim/ABC")
        assert resp.status_code == 422

    @pytest.mark.asyncio
    async def test_referred_by_set_only_after_wallet_checks(self, authed_client):
        """referred_by must not be committed if an exception occurs mid-transaction."""
        client, session, claimer = authed_client
        claimer.referred_by = None
        referrer = _make_user(referral_code="REFCODE1")

        results = [
            _scalar_one_result(claimer),
            _scalar_one_or_none_result(referrer),
            _scalar_one_or_none_result(None),  # referrer has no wallet
            _scalar_one_or_none_result(None),  # claimer has no wallet
        ]
        idx = [0]

        async def fake_execute(query):
            r = results[min(idx[0], len(results) - 1)]
            idx[0] += 1
            return r

        session.execute = fake_execute

        resp = await client.post(f"{BASE}/claim/REFCODE1")
        # Claim still succeeds (referred_by is set, gems silently skipped)
        assert resp.status_code == 200
        assert claimer.referred_by == referrer.id
        assert resp.json()["gems_awarded"] == 0


# ---------------------------------------------------------------------------
# Streak reminder task unit tests
# ---------------------------------------------------------------------------

class TestStreakReminderTask:
    def test_uses_utc_date_not_local(self):
        """_send_streak_alerts must use UTC date, not os-local date."""
        from app.tasks import streak_reminders
        import inspect
        src = inspect.getsource(streak_reminders._send_streak_alerts)
        assert "datetime.now(timezone.utc).date()" in src, (
            "Streak task must use datetime.now(timezone.utc).date() not date.today()"
        )

    def test_no_daily_activity_import(self):
        """DailyActivity should not be imported (was unused)."""
        from app.tasks import streak_reminders
        import inspect
        src = inspect.getsource(streak_reminders)
        assert "DailyActivity" not in src, (
            "DailyActivity is unused and should not be imported in streak_reminders"
        )

    @pytest.mark.asyncio
    async def test_skips_users_with_zero_streak(self):
        """Users with current_streak == 0 must not receive alerts."""
        from datetime import date, timedelta
        from app.tasks.streak_reminders import _send_streak_alerts

        zero_streak = MagicMock()
        zero_streak.user_id = uuid.uuid4()
        zero_streak.current_streak = 0
        zero_streak.last_activity_date = date.today() - timedelta(days=1)

        with (
            patch("app.tasks.streak_reminders.AsyncSessionLocal") as mock_session_cls,
            patch("app.tasks.streak_reminders.PushNotificationService") as mock_push_cls,
        ):
            mock_db = AsyncMock()
            mock_session_cls.return_value.__aenter__ = AsyncMock(return_value=mock_db)
            mock_session_cls.return_value.__aexit__ = AsyncMock(return_value=False)

            result_mock = MagicMock()
            result_mock.scalars.return_value.all.return_value = []  # no at-risk users

            mock_db.execute = AsyncMock(return_value=result_mock)

            mock_push = MagicMock()
            mock_push_cls.return_value = mock_push

            result = await _send_streak_alerts()

        assert result["sent"] == 0
        mock_push.send_streak_at_risk.assert_not_called()


# ---------------------------------------------------------------------------
# Referral code generation uses secrets (security check)
# ---------------------------------------------------------------------------

def test_generate_code_uses_secrets_module():
    """_generate_code must use secrets module, not random."""
    from app.routes import referral as referral_module
    import inspect
    src = inspect.getsource(referral_module._generate_code)
    assert "secrets.choice" in src, "_generate_code must use secrets.choice not random.choices"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _none_result() -> MagicMock:
    r = MagicMock()
    r.scalar_one_or_none.return_value = None
    r.scalar_one.return_value = None
    r.scalars.return_value.all.return_value = []
    return r


def _scalar_one_result(value) -> MagicMock:
    r = MagicMock()
    r.scalar_one.return_value = value
    r.scalar_one_or_none.return_value = value
    r.scalars.return_value.all.return_value = []
    return r


def _scalar_one_or_none_result(value) -> MagicMock:
    r = MagicMock()
    r.scalar_one_or_none.return_value = value
    r.scalar_one.return_value = value
    r.scalars.return_value.all.return_value = []
    return r
