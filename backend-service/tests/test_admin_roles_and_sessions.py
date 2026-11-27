"""Custom roles, who may revoke whom, and when a sign-in or session stops being valid."""
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock
from uuid import UUID, uuid4

import pytest
from sqlalchemy import delete, func, select, text
from sqlalchemy.exc import IntegrityError

from app.core import dependencies, firebase_auth, security
from app.core.config import settings
from app.core.security import create_access_token, decode_token, get_password_hash
from app.core.session_cookie import COOKIE_NAME
from app.core.token_blacklist import InactiveUserFlag, SessionCut
from app.models.proficiency import SkillType, UserProficiencyProfile, UserSkillScore
from app.models.rbac import AuditLog, Role
from app.models.user import RefreshToken, User
from app.services.auth_service import issue_refresh_token, refresh_lifetime_days
from app.services.email_service import EmailService
from tests.conftest import seed_admin_permissions

API = "/api/v1"
PASSWORD = "Passw0rd!x"
_LEVELS = {"user": 0, "admin": 1, "super_admin": 2}


async def _role(db, slug: str) -> Role:
    role = (await db.execute(select(Role).where(Role.slug == slug))).scalar_one_or_none()
    if role is None:
        role = Role(name=slug.replace("_", " ").title(), slug=slug, level=_LEVELS[slug], is_system=True, is_active=True)
        db.add(role)
        await db.commit()
    return role


async def _make(db, slug: str = "user", **fields) -> User:
    role = await _role(db, slug) if slug in _LEVELS else (
        await db.execute(select(Role).where(Role.slug == slug))
    ).scalar_one()
    tag = uuid4().hex[:8]
    values = {
        "email": f"{tag}@example.com", "username": f"u{tag}", "hashed_password": get_password_hash(PASSWORD),
        "is_verified": True, "is_active": True, "provider": ["local"],
    }
    values.update(fields)
    user = User(role_id=role.id, **values)
    db.add(user)
    await db.commit()
    await db.refresh(user, ["role"])
    return user


def _headers(user: User, signed_in: timedelta | None = None) -> dict:
    """`signed_in` is how long ago this session proved who it is; None is an older token without that."""
    claims = {"sub": str(user.id)}
    if signed_in is not None:
        claims["auth_time"] = int((datetime.now(timezone.utc) - signed_in).timestamp())
    return {"Authorization": f"Bearer {create_access_token(claims)}"}


_JUST_NOW = timedelta(0)


async def _owner(db, **fields) -> User:
    return await _make(db, "super_admin", **fields)


async def _role_of(db, user: User) -> str:
    await db.refresh(user, ["role"])
    return user.role.slug


@pytest.fixture(autouse=True)
async def permission_catalog(db_session):
    for slug in _LEVELS:
        await _role(db_session, slug)
    await seed_admin_permissions(db_session)


async def _create_role(client, actor, slug="editor", **body):
    payload = {"name": slug.title(), "slug": slug, **body}
    return await client.post(f"{API}/admin/rbac/roles", headers=_headers(actor), json=payload)


# ---------------------------------------------------------------- custom roles


async def test_super_admin_creates_delegates_assigns_and_deletes_a_role(async_client, db_session, super_admin_user):
    await _role(db_session, "user")
    boss = _headers(super_admin_user)
    member = await _make(db_session)

    made = await _create_role(async_client, super_admin_user, description="Edits courses")
    assert made.status_code == 201
    assert (made.json()["level"], made.json()["is_system"], made.json()["permissions"]) == (1, False, [])

    assigned = await async_client.put(f"{API}/admin/users/{member.id}/role", headers=boss, json={"slug": "editor"})
    assert assigned.status_code == 200
    assert await _role_of(db_session, member) == "editor"

    # An admin-level role with nothing delegated can open no guarded area.
    assert (await async_client.get(f"{API}/admin/users", headers=_headers(member))).status_code == 403

    put = f"{API}/admin/rbac/roles/editor/permissions"
    assert (await async_client.put(put, headers=boss, json={"permission_slugs": ["users:read"]})).status_code == 200
    assert (await async_client.get(f"{API}/admin/users", headers=_headers(member))).status_code == 200
    mine = await async_client.get(f"{API}/admin/rbac/me/permissions", headers=_headers(member))
    assert mine.json() == {"all": False, "permissions": ["users:read"]}

    held = await async_client.delete(f"{API}/admin/rbac/roles/editor", headers=boss)
    assert held.status_code == 409
    assert (await async_client.put(f"{API}/admin/users/{member.id}/role", headers=boss, json={"slug": "user"})).status_code == 200
    assert (await async_client.delete(f"{API}/admin/rbac/roles/editor", headers=boss)).status_code == 200
    assert (await db_session.execute(select(Role).where(Role.slug == "editor"))).scalar_one_or_none() is None
    actions = set((await db_session.execute(select(AuditLog.action).where(AuditLog.resource_type == "role"))).scalars())
    assert {"role_create", "role_permissions_update", "role_delete"} <= actions


async def test_a_role_can_be_created_with_permissions(async_client, super_admin_user):
    made = await _create_role(async_client, super_admin_user, permission_slugs=["users:read"])
    assert made.status_code == 201
    assert [p["slug"] for p in made.json()["permissions"]] == ["users:read"]


@pytest.mark.parametrize(
    "payload, status_code",
    [
        ({"name": "Boss", "slug": "super_admin"}, 409),
        ({"name": "Tester", "slug": "test"}, 409),
        ({"name": "Bad", "slug": "Has Space"}, 422),
        ({"name": "  ", "slug": "blank_name"}, 422),
        ({"name": "Unknown", "slug": "unknown_perm", "permission_slugs": ["nope:read"]}, 422),
    ],
)
async def test_invalid_roles_are_refused(async_client, super_admin_user, payload, status_code):
    r = await async_client.post(f"{API}/admin/rbac/roles", headers=_headers(super_admin_user), json=payload)
    assert r.status_code == status_code


async def test_duplicate_role_names_are_refused(async_client, super_admin_user):
    assert (await _create_role(async_client, super_admin_user)).status_code == 201
    again = await async_client.post(
        f"{API}/admin/rbac/roles", headers=_headers(super_admin_user), json={"name": "EDITOR", "slug": "editor2"}
    )
    assert again.status_code == 409


async def test_only_a_super_admin_manages_roles(async_client, super_admin_user, admin_user):
    assert (await _create_role(async_client, admin_user)).status_code == 403
    r = await async_client.delete(f"{API}/admin/rbac/roles/admin", headers=_headers(admin_user))
    assert r.status_code == 403


async def test_built_in_roles_cannot_be_deleted(async_client, super_admin_user, admin_user):
    r = await async_client.delete(f"{API}/admin/rbac/roles/admin", headers=_headers(super_admin_user))
    assert r.status_code == 400


async def test_a_custom_role_gets_the_short_admin_session(async_client, db_session, super_admin_user):
    await _create_role(async_client, super_admin_user)
    member = await _make(db_session, "editor")
    assert await refresh_lifetime_days(db_session, member.id) == min(
        settings.REFRESH_TOKEN_EXPIRE_DAYS, settings.REFRESH_TOKEN_EXPIRE_DAYS_PRIVILEGED
    )


async def test_a_custom_role_can_sign_in_to_the_admin_web_with_google(async_client, db_session, super_admin_user, monkeypatch):
    await _create_role(async_client, super_admin_user)
    member = await _make(db_session, "editor", provider=["google"])
    monkeypatch.setattr(settings, "GOOGLE_ADMIN_CLIENT_ID", "admin-client-id")
    monkeypatch.setattr(
        security, "verify_google_token",
        AsyncMock(return_value={"email": member.email, "email_verified": True, "name": "e", "picture": None}),
    )
    r = await async_client.post(f"{API}/auth/google", json={"id_token": "x", "source": "admin"})
    assert r.status_code == 200, r.text
    assert r.json()["role"] == "editor"


async def test_roles_with_the_ids_the_migrations_seed_can_be_listed(async_client, db_session, super_admin_user):
    db_session.add(Role(
        id=UUID("00000000-0000-0000-0000-000000000004"), name="Test", slug="test",
        level=0, is_system=True, is_active=True,
    ))
    await db_session.commit()
    boss = _headers(super_admin_user)
    listed = await async_client.get(f"{API}/admin/rbac/roles", headers=boss)
    assert listed.status_code == 200
    assert "test" in [r["slug"] for r in listed.json()]
    assert (await async_client.get(f"{API}/admin/rbac/roles/test", headers=boss)).status_code == 200


# ---------------------------------------------------------------- revoking admins


async def test_an_admin_cannot_switch_a_super_admin_back_on(async_client, db_session, super_admin_user, admin_user):
    target = await _make(db_session, "super_admin", is_active=False)
    for url in (f"{API}/admin/users/{target.id}/status", f"{API}/admin/users/{target.id}"):
        r = await async_client.put(url, headers=_headers(admin_user), json={"is_active": True})
        assert r.status_code == 403
    await db_session.refresh(target)
    assert target.is_active is False


async def test_recently_signed_in_super_admin_can_revoke_an_unlisted_one(async_client, db_session):
    actor, target = await _owner(db_session), await _make(db_session, "super_admin")
    await _role(db_session, "user")
    h = _headers(actor, _JUST_NOW)
    off = await async_client.put(f"{API}/admin/users/{target.id}/status", headers=h, json={"is_active": False})
    on = await async_client.put(f"{API}/admin/users/{target.id}/status", headers=h, json={"is_active": True})
    demote = await async_client.put(f"{API}/admin/users/{target.id}/role", headers=h, json={"slug": "user"})
    assert (off.status_code, on.status_code, demote.status_code) == (200, 200, 200)
    assert await _role_of(db_session, target) == "user"


@pytest.mark.parametrize("signed_in", [None, timedelta(hours=1)])
async def test_revoking_a_super_admin_needs_a_recent_sign_in(async_client, db_session, signed_in):
    # A sign-in elsewhere (last_login) must not vouch for an old session.
    actor = await _make(db_session, "super_admin", last_login=datetime.now(timezone.utc))
    target = await _make(db_session, "super_admin")
    await _role(db_session, "user")
    r = await async_client.put(f"{API}/admin/users/{target.id}/role", headers=_headers(actor, signed_in), json={"slug": "user"})
    assert r.status_code == 403
    assert r.json()["error"]["details"] == {"reason": "recent_sign_in_required"}


async def test_a_super_admin_listed_in_server_config_is_protected(async_client, db_session, monkeypatch):
    actor, target = await _owner(db_session), await _make(db_session, "super_admin", email="owner@example.com")
    await _role(db_session, "user")
    monkeypatch.setattr(settings, "SUPER_ADMIN_EMAIL_WHITELIST", "owner@example.com")
    h = _headers(actor, _JUST_NOW)
    demote = await async_client.put(f"{API}/admin/users/{target.id}/role", headers=h, json={"slug": "user"})
    off = await async_client.put(f"{API}/admin/users/{target.id}/status", headers=h, json={"is_active": False})
    assert (demote.status_code, off.status_code) == (403, 403)
    assert "protected" in demote.text


async def test_the_only_super_admin_cannot_close_their_own_account(async_client, db_session):
    only = await _owner(db_session)
    for url in (f"{API}/users/me", f"{API}/users/me/permanent"):
        assert (await async_client.delete(url, headers=_headers(only, _JUST_NOW))).status_code == 409


async def test_disabling_an_account_ends_its_sessions_for_good(async_client, db_session, super_admin_user):
    member = await _make(db_session)
    await issue_refresh_token(db_session, member.id)
    url = f"{API}/admin/users/{member.id}/status"
    assert (await async_client.put(url, headers=_headers(super_admin_user), json={"is_active": False})).status_code == 200
    rows = (await db_session.execute(select(RefreshToken).where(RefreshToken.user_id == member.id))).scalars().all()
    await db_session.refresh(rows[0])
    assert rows[0].is_revoked is True


# ---------------------------------------------------------------- allowlist


def _claims(email: str) -> dict:
    return {"email": email, "email_verified": True, "uid": "x", "firebase": {"sign_in_provider": "google.com"}}


async def test_a_demotion_survives_the_next_sign_in(db_session, monkeypatch):
    await _owner(db_session)
    await _role(db_session, "admin")
    member = await _make(db_session, email="listed@example.com", provider=["google"])
    monkeypatch.setattr(settings, "ADMIN_EMAIL_WHITELIST", member.email)
    user = await firebase_auth.get_or_create_user_from_claims(db_session, _claims(member.email))
    assert await _role_of(db_session, user) == "user"


async def test_the_allowlist_restores_a_super_admin_when_none_is_left(db_session, monkeypatch):
    await _role(db_session, "super_admin")
    member = await _make(db_session, email="owner@example.com", provider=["google"])
    monkeypatch.setattr(settings, "SUPER_ADMIN_EMAIL_WHITELIST", member.email)
    user = await firebase_auth.get_or_create_user_from_claims(db_session, _claims(member.email))
    assert await _role_of(db_session, user) == "super_admin"


@pytest.mark.parametrize("verified, status_code", [(True, 200), (False, 400)])
async def test_google_route_grants_the_allowlisted_role_only_on_a_verified_email(
    async_client, db_session, monkeypatch, verified, status_code
):
    await _role(db_session, "user")
    await _role(db_session, "admin")
    email = "newadmin@example.com"
    monkeypatch.setattr(settings, "ADMIN_EMAIL_WHITELIST", email)
    monkeypatch.setattr(
        security, "verify_google_token",
        AsyncMock(return_value={"email": email, "email_verified": verified, "name": "n", "picture": None}),
    )
    r = await async_client.post(f"{API}/auth/google", json={"id_token": "x", "source": "app"})
    assert r.status_code == status_code, r.text
    created = (await db_session.execute(select(User).where(User.email == email))).scalar_one_or_none()
    if verified:
        assert r.json()["role"] == "admin"
    else:
        assert created is None


# ---------------------------------------------------------------- email letter case


async def test_email_letter_case_does_not_matter(async_client, db_session, monkeypatch):
    await _role(db_session, "user")
    monkeypatch.setattr(EmailService, "send_verification_email", AsyncMock())
    body = {"email": "Mixed.Case@example.com", "username": "mixedone", "password": PASSWORD}
    assert (await async_client.post(f"{API}/auth/register", json=body)).status_code == 201
    for typed in ("mixed.case@example.com", "MIXED.CASE@example.com"):
        r = await async_client.post(f"{API}/auth/login", json={"email": typed, "password": PASSWORD})
        assert r.status_code == 200
    second = await async_client.post(
        f"{API}/auth/register", json={**body, "email": "mixed.case@EXAMPLE.com", "username": "mixedtwo"}
    )
    assert second.status_code == 400


async def test_an_older_mixed_case_account_still_signs_in(async_client, db_session):
    await _make(db_session, email="Old.Account@example.com")
    r = await async_client.post(f"{API}/auth/login", json={"email": "old.account@example.com", "password": PASSWORD})
    assert r.status_code == 200


@pytest.fixture
async def data_from_before_the_unique_index(db_session):
    await db_session.execute(text("DROP INDEX uq_users_email_lower"))
    await db_session.commit()
    yield
    await db_session.rollback()
    await db_session.execute(delete(User).where(func.lower(User.email) == "twin@example.com"))
    await db_session.execute(text("CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email))"))
    await db_session.commit()


async def test_accounts_differing_only_by_case_each_stay_reachable(
    async_client, db_session, data_from_before_the_unique_index
):
    first = await _make(db_session, email="Twin@example.com")
    second = await _make(db_session, email="twin@example.com", hashed_password=get_password_hash("Other0ne!x"))
    a = await async_client.post(f"{API}/auth/login", json={"email": first.email, "password": PASSWORD})
    b = await async_client.post(f"{API}/auth/login", json={"email": second.email, "password": "Other0ne!x"})
    assert (a.json()["user_id"], b.json()["user_id"]) == (str(first.id), str(second.id))


# ---------------------------------------------------------------- sessions


async def test_changing_the_password_ends_the_old_access_token(async_client, db_session, monkeypatch):
    monkeypatch.setattr(EmailService, "send_password_changed_email", AsyncMock())
    user = await _make(db_session)
    login = await async_client.post(f"{API}/auth/login", json={"email": user.email, "password": PASSWORD})
    old = {"Authorization": f"Bearer {login.json()['access_token']}"}
    assert (await async_client.get(f"{API}/auth/me", headers=old)).status_code == 200

    changed = await async_client.post(
        f"{API}/auth/change-password", headers=old,
        json={"current_password": PASSWORD, "new_password": "N3wPassw0rd!x"},
    )
    assert changed.status_code == 200
    assert (await async_client.get(f"{API}/auth/me", headers=old)).status_code == 401

    fresh = await async_client.post(f"{API}/auth/login", json={"email": user.email, "password": "N3wPassw0rd!x"})
    new = {"Authorization": f"Bearer {fresh.json()['access_token']}"}
    assert (await async_client.get(f"{API}/auth/me", headers=new)).status_code == 200
    # A refreshed token is bound too.
    rotated = await async_client.post(f"{API}/auth/refresh", json={"refresh_token": fresh.json()["refresh_token"]})
    bearer = {"Authorization": f"Bearer {rotated.json()['access_token']}"}
    assert (await async_client.get(f"{API}/auth/me", headers=bearer)).status_code == 200


async def test_reset_password_verifies_the_account_so_google_keeps_the_new_password(async_client, db_session, monkeypatch):
    monkeypatch.setattr(EmailService, "send_password_reset_email", AsyncMock())
    monkeypatch.setattr(EmailService, "send_password_changed_email", AsyncMock())
    user = await _make(db_session, is_verified=False)
    await async_client.post(f"{API}/auth/forgot-password", json={"email": user.email})
    token = EmailService.send_password_reset_email.call_args.kwargs["reset_token"]
    done = await async_client.post(f"{API}/auth/reset-password", json={"token": token, "new_password": "N3wPassw0rd!x"})
    assert done.status_code == 200
    await db_session.refresh(user)
    assert user.is_verified is True

    await firebase_auth.get_or_create_user_from_claims(db_session, _claims(user.email))
    r = await async_client.post(f"{API}/auth/login", json={"email": user.email, "password": "N3wPassw0rd!x"})
    assert r.status_code == 200


async def test_a_raw_firebase_token_does_not_open_admin_routes(async_client, super_admin_user, monkeypatch):
    claims = _claims(super_admin_user.email)
    monkeypatch.setattr(dependencies, "verify_firebase_token", lambda token: claims)
    bearer = {"Authorization": "Bearer not-our-token"}
    assert (await async_client.get(f"{API}/admin/rbac/roles", headers=bearer)).status_code == 403
    assert (await async_client.get(f"{API}/admin/rbac/me/permissions", headers=bearer)).status_code == 403
    assert (await async_client.get(f"{API}/auth/me", headers=bearer)).status_code == 200


async def test_users_me_reports_admin_rights(async_client, super_admin_user, admin_user):
    boss = (await async_client.get(f"{API}/users/me", headers=_headers(super_admin_user))).json()
    boss = boss.get("data", boss)
    plain = (await async_client.get(f"{API}/users/me", headers=_headers(admin_user))).json()
    plain = plain.get("data", plain)
    assert (boss["is_admin"], boss["is_super_admin"]) == (True, True)
    assert (plain["is_admin"], plain["is_super_admin"]) == (True, False)


async def test_otp_admin_sign_in_is_audited(async_client, db_session, super_admin_user, monkeypatch):
    monkeypatch.setattr(settings, "ADMIN_CODE_LOGIN_ENABLED", True)
    r = await async_client.post(f"{API}/auth/admin/verify-otp", json={"email": super_admin_user.email, "otp": "000000"})
    assert r.status_code == 400
    rows = (await db_session.execute(select(AuditLog.action).where(AuditLog.resource_type == "auth"))).scalars().all()
    assert "login_failed" in rows


async def test_the_database_refuses_a_second_account_differing_only_by_case(db_session):
    await _make(db_session, email="unique@example.com")
    with pytest.raises(IntegrityError):
        await _make(db_session, email="Unique@Example.com")
    await db_session.rollback()


# ---------------------------------------------------------------- recent sign-in


async def _sign_in(client, user: User) -> dict:
    r = await client.post(f"{API}/auth/login", json={"email": user.email, "password": PASSWORD})
    assert r.status_code == 200, r.text
    return r.json()


async def test_refreshing_keeps_the_original_sign_in_time(async_client, db_session):
    tokens = await _sign_in(async_client, await _make(db_session))
    first = decode_token(tokens["access_token"])["auth_time"]
    renewed = (await async_client.post(f"{API}/auth/refresh", json={"refresh_token": tokens["refresh_token"]})).json()
    assert decode_token(renewed["access_token"])["auth_time"] == first
    assert decode_token(renewed["refresh_token"])["auth_time"] == first


async def test_a_session_from_before_sign_in_times_stays_unproven_after_refresh(async_client, db_session):
    user = await _make(db_session)
    legacy = await issue_refresh_token(db_session, user.id)
    renewed = (await async_client.post(f"{API}/auth/refresh", json={"refresh_token": legacy})).json()
    assert "auth_time" not in decode_token(renewed["access_token"])


@pytest.mark.parametrize("path", ["/users/me", "/users/me/permanent"])
@pytest.mark.parametrize("signed_in", [None, timedelta(minutes=16)])
async def test_deleting_the_account_needs_a_recent_sign_in(async_client, db_session, path, signed_in):
    user = await _make(db_session)
    r = await async_client.delete(f"{API}{path}", headers=_headers(user, signed_in))
    assert r.status_code == 403
    assert r.json()["error"]["details"] == {"reason": "recent_sign_in_required"}
    await db_session.refresh(user)
    assert user.is_active is True


async def test_a_learner_who_just_signed_in_can_delete_the_account(async_client, db_session):
    """Self-deletion failed for everyone: it filtered tables that have no user_id column."""
    user = await _make(db_session)
    user_id = user.id
    profile = UserProficiencyProfile(user_id=user_id)
    db_session.add(profile)
    await db_session.flush()
    db_session.add(UserSkillScore(profile_id=profile.id, skill=SkillType.VOCABULARY, score=10.0))
    await db_session.commit()
    tokens = await _sign_in(async_client, user)
    r = await async_client.delete(
        f"{API}/users/me/permanent", headers={"Authorization": f"Bearer {tokens['access_token']}"}
    )
    assert r.status_code == 200, r.text
    db_session.expire_all()
    for model, column in ((User, User.id), (UserProficiencyProfile, UserProficiencyProfile.user_id)):
        assert await db_session.scalar(select(func.count()).select_from(model).where(column == user_id)) == 0
    assert await db_session.scalar(select(func.count()).select_from(UserSkillScore)) == 0
    assert await db_session.scalar(select(func.count()).select_from(RefreshToken).where(RefreshToken.user_id == user_id)) == 0


# ---------------------------------------------------------------- session cuts for ai-service


async def test_password_change_and_disabling_tell_ai_service_to_drop_older_tokens(
    async_client, db_session, super_admin_user, monkeypatch
):
    monkeypatch.setattr(EmailService, "send_password_changed_email", AsyncMock())
    cut = AsyncMock()
    monkeypatch.setattr(SessionCut, "publish", cut)
    user = await _make(db_session)
    tokens = await _sign_in(async_client, user)
    r = await async_client.post(
        f"{API}/auth/change-password", headers={"Authorization": f"Bearer {tokens['access_token']}"},
        json={"current_password": PASSWORD, "new_password": "N3wPassw0rd!x"},
    )
    assert r.status_code == 200
    cut.assert_awaited_once_with(user.id)


async def test_disabling_publishes_a_cut_that_outlives_reactivation(monkeypatch):
    store: dict[str, str] = {}

    class FakeRedis:
        async def setex(self, key, ttl, value):
            store[key] = value

        async def delete(self, key):
            store.pop(key, None)

    async def instance():
        return FakeRedis()

    monkeypatch.setattr("app.core.token_blacklist.RedisClient.get_instance", instance)
    await InactiveUserFlag.sync("u1", False)
    await InactiveUserFlag.sync("u1", True)
    assert list(store) == ["user:sessions-cut:u1"]
    assert int(store["user:sessions-cut:u1"]) > 0


# ---------------------------------------------------------------- admin code sign-in


@pytest.mark.parametrize("path", ["login", "request-otp", "verify-otp"])
async def test_password_and_code_admin_sign_in_are_off_by_default(async_client, super_admin_user, path):
    r = await async_client.post(
        f"{API}/auth/admin/{path}", json={"email": super_admin_user.email, "password": "x", "otp": "000000"}
    )
    assert r.status_code == 404


# ---------------------------------------------------------------- admin web cookie session

ADMIN_ORIGIN = {"Origin": "https://admin.lexilingo.me"}


async def _google_admin(client, db, monkeypatch, headers=ADMIN_ORIGIN, **body):
    user = await _make(db, "admin", provider=["google"])
    monkeypatch.setattr(settings, "GOOGLE_ADMIN_CLIENT_ID", "admin-client-id")
    monkeypatch.setattr(
        security, "verify_google_token",
        AsyncMock(return_value={"email": user.email, "email_verified": True, "name": "a", "picture": None}),
    )
    payload = {"id_token": "x", "source": "admin", "session": "cookie", **body}
    return await client.post(f"{API}/auth/google", json=payload, headers=headers)


async def test_cookie_session_keeps_the_refresh_token_away_from_scripts(async_client, db_session, monkeypatch):
    r = await _google_admin(async_client, db_session, monkeypatch)
    assert r.status_code == 200, r.text
    assert r.json()["refresh_token"] == "" and r.json()["access_token"]
    cookie = r.headers["set-cookie"].lower()
    for flag in (f"{COOKIE_NAME}=", "httponly", "samesite=strict", "path=/api/v1/auth", "max-age="):
        assert flag in cookie
    first = async_client.cookies.get(COOKIE_NAME)

    renewed = await async_client.post(f"{API}/auth/refresh", json={"session": "cookie"}, headers=ADMIN_ORIGIN)
    assert renewed.status_code == 200, renewed.text
    assert renewed.json()["refresh_token"] == "" and renewed.json()["access_token"]
    assert async_client.cookies.get(COOKIE_NAME) != first

    current = async_client.cookies.get(COOKIE_NAME)
    out = await async_client.post(f"{API}/auth/logout", json={"session": "cookie"}, headers=ADMIN_ORIGIN)
    assert out.status_code == 200
    assert async_client.cookies.get(COOKIE_NAME) is None
    reused = await async_client.post(f"{API}/auth/refresh", json={"refresh_token": current})
    assert reused.status_code == 401


async def test_the_cookie_is_marked_secure_in_production(monkeypatch):
    from fastapi import Response
    from app.core.session_cookie import set_refresh_cookie

    monkeypatch.setattr(settings, "APP_ENV", "production")
    response = Response()
    set_refresh_cookie(response, "t", 7)
    assert "secure" in response.headers["set-cookie"].lower()


@pytest.mark.parametrize("origin", ["https://www.lexilingo.me", "https://evil.example", None])
async def test_only_the_admin_web_may_use_the_cookie(async_client, db_session, monkeypatch, origin):
    assert (await _google_admin(async_client, db_session, monkeypatch)).status_code == 200
    headers = {"Origin": origin} if origin else {}
    for path in ("refresh", "logout"):
        r = await async_client.post(f"{API}/auth/{path}", json={"session": "cookie"}, headers=headers)
        assert r.status_code == 403
    # Nothing was spent: the admin web can still renew.
    ok = await async_client.post(f"{API}/auth/refresh", json={"session": "cookie"}, headers=ADMIN_ORIGIN)
    assert ok.status_code == 200


async def test_local_origins_work_outside_production_only(async_client, db_session, monkeypatch):
    local = {"Origin": "http://localhost:5173"}
    assert (await _google_admin(async_client, db_session, monkeypatch, headers=local)).status_code == 200
    monkeypatch.setattr(settings, "APP_ENV", "production")
    r = await async_client.post(f"{API}/auth/refresh", json={"session": "cookie"}, headers=local)
    assert r.status_code == 403


async def test_a_stored_token_moves_into_the_cookie(async_client, db_session):
    user = await _make(db_session, "admin")
    stored = (await _sign_in(async_client, user))["refresh_token"]
    r = await async_client.post(
        f"{API}/auth/refresh", json={"refresh_token": stored, "session": "cookie"}, headers=ADMIN_ORIGIN
    )
    assert r.status_code == 200
    assert r.json()["refresh_token"] == ""
    assert async_client.cookies.get(COOKIE_NAME)


async def test_without_opting_in_sessions_work_as_before(async_client, db_session, monkeypatch):
    r = await _google_admin(async_client, db_session, monkeypatch, headers={}, session="token")
    assert r.status_code == 200
    assert r.json()["refresh_token"] and "set-cookie" not in r.headers
    assert (await async_client.post(f"{API}/auth/refresh", json={})).status_code == 422


# ---------------------------------------------------------------- shared account matching


async def test_google_sign_in_keeps_a_picture_the_learner_chose(async_client, db_session, monkeypatch):
    await _role(db_session, "user")
    user = await _make(db_session, avatar_url="/media/avatars/mine.png")
    monkeypatch.setattr(
        security, "verify_google_token",
        AsyncMock(return_value={"email": user.email, "email_verified": True, "name": "n", "picture": "https://g/p.png"}),
    )
    r = await async_client.post(f"{API}/auth/google", json={"id_token": "x", "source": "app"})
    assert r.status_code == 200, r.text
    await db_session.refresh(user)
    assert user.avatar_url == "/media/avatars/mine.png"
