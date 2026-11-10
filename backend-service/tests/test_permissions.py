"""Admin permissions are enforced per route, editable per role, and seeded without changing anyone's access."""
from types import SimpleNamespace
from uuid import uuid4

import pytest
import pytest_asyncio
from fastapi import HTTPException
from fastapi.routing import APIRoute
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.database import Base
from app.core.dependencies import get_current_admin, get_current_super_admin, require_permission, require_resource
from app.core.permissions import PERMISSION_CATALOG, all_slugs
from app.main import app
from app.models.rbac import AuditLog, Permission, Role, RolePermission
from app.routes import rbac
from app.services.permission_seed import ADMIN_WITHHELD, seed_permissions

TABLES = [Role, Permission, RolePermission, AuditLog]


@pytest_asyncio.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(lambda c: Base.metadata.create_all(c, tables=[m.__table__ for m in TABLES]))
    async with async_sessionmaker(engine, expire_on_commit=False)() as session:
        for slug, level in (("admin", 1), ("super_admin", 2)):
            session.add(Role(id=uuid4(), name=slug, slug=slug, level=level))
        await session.commit()
        await session.run_sync(lambda s: seed_permissions(s.connection(), PERMISSION_CATALOG))
        await session.commit()
        yield session
    await engine.dispose()


async def _role(db, slug):
    return (await db.execute(select(Role).where(Role.slug == slug))).scalar_one()


async def _admin(db, level=1):
    role = await _role(db, "super_admin" if level >= 2 else "admin")
    return SimpleNamespace(id=uuid4(), username="boss", role_id=role.id, role_level=level)


def _request(method="GET"):
    return SimpleNamespace(method=method, state=SimpleNamespace(), client=None, headers={})


# ── the guard ────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_a_default_admin_passes_every_guard_it_could_pass_before(db):
    admin = await _admin(db)
    for resource, method in (("courses", "DELETE"), ("content", "POST"), ("shop", "PUT"), ("banners", "GET")):
        assert await require_resource(resource)(_request(method), admin, db) is admin
    assert await require_permission("gifts:grant")(admin, db) is admin


@pytest.mark.asyncio
async def test_removing_a_permission_makes_that_action_403_but_not_the_others(db):
    admin = await _admin(db)
    role = await _role(db, "admin")
    perm = (await db.execute(select(Permission).where(Permission.slug == "courses:delete"))).scalar_one()
    await db.execute(RolePermission.__table__.delete().where(
        RolePermission.role_id == role.id, RolePermission.permission_id == perm.id))
    await db.commit()

    with pytest.raises(HTTPException) as err:
        await require_resource("courses")(_request("DELETE"), admin, db)
    assert err.value.status_code == 403 and "courses:delete" in err.value.detail
    assert await require_resource("courses")(_request("PUT"), admin, db) is admin


@pytest.mark.asyncio
async def test_manage_acts_as_a_wildcard_for_its_resource(db):
    admin = await _admin(db)
    role = await _role(db, "admin")
    await db.execute(RolePermission.__table__.delete().where(RolePermission.role_id == role.id))
    manage = (await db.execute(select(Permission).where(Permission.slug == "courses:manage"))).scalar_one()
    db.add(RolePermission(role_id=role.id, permission_id=manage.id))
    await db.commit()

    assert await require_resource("courses")(_request("DELETE"), admin, db) is admin
    with pytest.raises(HTTPException):
        await require_resource("shop")(_request("GET"), admin, db)


@pytest.mark.asyncio
async def test_super_admin_passes_even_with_no_permission_rows(db):
    root = await _admin(db, 2)
    await db.execute(RolePermission.__table__.delete())
    await db.commit()
    assert await require_resource("courses")(_request("DELETE"), root, db) is root


def test_every_guarded_admin_route_names_a_permission_or_needs_a_super_admin():
    plain_admin_ok = {"/api/v1/admin/rbac/me/permissions"}
    offenders = []
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue

        def calls(dep):
            yield dep.call
            for sub in dep.dependencies:
                yield from calls(sub)

        found = list(calls(route.dependant))
        if get_current_admin not in found:
            continue
        named = [getattr(c, "__qualname__", "") for c in found]
        if get_current_super_admin in found or any(n.startswith(("require_permission.", "require_resource.")) for n in named):
            continue
        if route.path not in plain_admin_ok:
            offenders.append(f"{sorted(route.methods)[0]} {route.path}")
    assert offenders == []


def test_catalog_slugs_are_unique_and_well_formed():
    slugs = all_slugs()
    assert len(slugs) == len(set(slugs))
    assert all(":" in s for s in slugs)


# ── seeding ──────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_seeding_twice_changes_nothing_and_withholds_wildcards_from_admin(db):
    before = (await db.execute(select(func.count()).select_from(Permission))).scalar(), \
        (await db.execute(select(func.count()).select_from(RolePermission))).scalar()
    await db.run_sync(lambda s: seed_permissions(s.connection(), PERMISSION_CATALOG))
    await db.commit()
    after = (await db.execute(select(func.count()).select_from(Permission))).scalar(), \
        (await db.execute(select(func.count()).select_from(RolePermission))).scalar()
    assert before == after

    admin = await _role(db, "admin")
    granted = set((await db.execute(
        select(Permission.slug).join(RolePermission, RolePermission.permission_id == Permission.id)
        .where(RolePermission.role_id == admin.id))).scalars().all())
    assert granted == set(all_slugs()) - ADMIN_WITHHELD


# ── editing ──────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_super_admin_replaces_a_roles_permissions_and_it_is_audited(db):
    root = await _admin(db, 2)
    result = await rbac.set_role_permissions(
        "admin", rbac.RolePermissionsUpdate(permission_slugs=["courses:read", "gifts:read"]), _request(), root, db
    )
    assert sorted(p.slug for p in result.permissions) == ["courses:read", "gifts:read"]
    (audit,) = (await db.execute(select(AuditLog))).scalars().all()
    assert audit.action == "role_permissions_update" and "removed" in audit.details


@pytest.mark.asyncio
async def test_super_admin_role_and_unknown_permissions_are_refused(db):
    root = await _admin(db, 2)
    with pytest.raises(HTTPException) as err:
        await rbac.set_role_permissions("super_admin", rbac.RolePermissionsUpdate(permission_slugs=[]), _request(), root, db)
    assert err.value.status_code == 400
    with pytest.raises(HTTPException) as err:
        await rbac.set_role_permissions("admin", rbac.RolePermissionsUpdate(permission_slugs=["nope:x"]), _request(), root, db)
    assert err.value.status_code == 422


@pytest.mark.asyncio
async def test_my_permissions_lists_slugs_for_admin_and_everything_for_super(db):
    admin = await _admin(db)
    mine = await rbac.my_permissions(admin, db)
    assert mine["all"] is False and "gifts:grant" in mine["permissions"] and "users:delete" not in mine["permissions"]
    assert (await rbac.my_permissions(await _admin(db, 2), db))["all"] is True
