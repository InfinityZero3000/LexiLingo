"""Custom roles, who may revoke whom, and when a sign-in or session stops being valid."""
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock
from uuid import UUID, uuid4

import pytest
from sqlalchemy import select

from app.core import dependencies, firebase_auth, security
from app.core.config import settings
from app.core.security import create_access_token, get_password_hash
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


def _headers(user: User) -> dict:
    return {"Authorization": f"Bearer {create_access_token({'sub': str(user.id)})}"}


async def _owner(db, **fields) -> User:
    """A super admin who signed in a moment ago."""
    fields.setdefault("last_login", datetime.now(timezone.utc))
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
    off = await async_client.put(f"{API}/admin/users/{target.id}/status", headers=_headers(actor), json={"is_active": False})
    on = await async_client.put(f"{API}/admin/users/{target.id}/status", headers=_headers(actor), json={"is_active": True})
    demote = await async_client.put(f"{API}/admin/users/{target.id}/role", headers=_headers(actor), json={"slug": "user"})
    assert (off.status_code, on.status_code, demote.status_code) == (200, 200, 200)
    assert await _role_of(db_session, target) == "user"


@pytest.mark.parametrize("last_login", [None, datetime.now(timezone.utc) - timedelta(hours=1)])
async def test_revoking_a_super_admin_needs_a_recent_sign_in(async_client, db_session, last_login):
    actor = await _make(db_session, "super_admin", last_login=last_login)
    target = await _make(db_session, "super_admin")
    await _role(db_session, "user")
    r = await async_client.put(f"{API}/admin/users/{target.id}/role", headers=_headers(actor), json={"slug": "user"})
    assert r.status_code == 403
    assert "recent sign-in" in r.text


async def test_a_super_admin_listed_in_server_config_is_protected(async_client, db_session, monkeypatch):
    actor, target = await _owner(db_session), await _make(db_session, "super_admin", email="owner@example.com")
    await _role(db_session, "user")
    monkeypatch.setattr(settings, "SUPER_ADMIN_EMAIL_WHITELIST", "owner@example.com")
    demote = await async_client.put(f"{API}/admin/users/{target.id}/role", headers=_headers(actor), json={"slug": "user"})
    off = await async_client.put(f"{API}/admin/users/{target.id}/status", headers=_headers(actor), json={"is_active": False})
    assert (demote.status_code, off.status_code) == (403, 403)
    assert "protected" in demote.text


async def test_the_only_super_admin_cannot_close_their_own_account(async_client, db_session):
    only = await _owner(db_session)
    for url in (f"{API}/users/me", f"{API}/users/me/permanent"):
        assert (await async_client.delete(url, headers=_headers(only))).status_code == 409


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


@pytest.mark.parametrize("verified, expected", [(True, "admin"), (False, "user")])
async def test_google_route_grants_the_allowlisted_role_only_on_a_verified_email(
    async_client, db_session, monkeypatch, verified, expected
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
    assert r.status_code == 200
    assert r.json()["role"] == expected


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


async def test_accounts_differing_only_by_case_each_stay_reachable(async_client, db_session):
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


async def test_otp_admin_sign_in_is_audited(async_client, db_session, super_admin_user):
    r = await async_client.post(f"{API}/auth/admin/verify-otp", json={"email": super_admin_user.email, "otp": "000000"})
    assert r.status_code == 400
    rows = (await db_session.execute(select(AuditLog.action).where(AuditLog.resource_type == "auth"))).scalars().all()
    assert "login_failed" in rows
