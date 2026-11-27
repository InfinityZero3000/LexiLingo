"""Banner, category and account-status rules the admin web can reach."""

import uuid

import pytest

from app.models.rbac import Role
from app.models.user import User

API = "/api/v1"
BANNER = {"title": "B", "image_url": "https://example.com/a.png"}


@pytest.mark.parametrize(
    "bad",
    [
        {"title": None},
        {"priority": None},
        {"priority": 10**12},
        {"position": None},
        {"is_active": None},
        {"target_min_level": "Z9"},
        {"start_at": "2027-01-02T00:00:00Z", "end_at": "2027-01-01T00:00:00Z"},
    ],
)
async def test_invalid_banner_update_is_422(async_client, admin_headers, bad):
    created = await async_client.post(f"{API}/banners", json=BANNER, headers=admin_headers)
    response = await async_client.put(
        f"{API}/banners/{created.json()['data']['id']}", json=bad, headers=admin_headers
    )
    assert response.status_code == 422, response.text


async def test_banner_end_cannot_be_moved_before_the_stored_start(async_client, admin_headers):
    created = await async_client.post(
        f"{API}/banners", json={**BANNER, "start_at": "2027-01-02T00:00:00Z"}, headers=admin_headers
    )
    response = await async_client.put(
        f"{API}/banners/{created.json()['data']['id']}",
        json={"end_at": "2027-01-01T00:00:00Z"},
        headers=admin_headers,
    )
    assert response.status_code == 422, response.text


async def test_duplicate_category_name_is_400_on_create_and_rename(async_client, admin_headers):
    async def create(name, slug):
        return await async_client.post(
            f"{API}/categories", json={"name": name, "slug": slug}, headers=admin_headers
        )

    assert (await create("Travel", "travel")).status_code == 201
    assert (await create("Travel", "travel-2")).status_code == 400
    other = await create("Work", "work")
    renamed = await async_client.put(
        f"{API}/categories/{other.json()['data']['id']}",
        json={"name": "Travel"},
        headers=admin_headers,
    )
    assert renamed.status_code == 400, renamed.text


async def test_an_admin_cannot_deactivate_themselves_through_the_profile_update(
    async_client, db_session, super_admin_user, super_admin_headers
):
    response = await async_client.put(
        f"{API}/admin/users/{super_admin_user.id}",
        json={"is_active": False},
        headers=super_admin_headers,
    )
    assert response.status_code == 400, response.text
    await db_session.refresh(super_admin_user)
    assert super_admin_user.is_active is True


@pytest.mark.parametrize("suffix", ["", "/status"])
async def test_an_admin_cannot_reactivate_a_super_admin(
    async_client, db_session, admin_headers, suffix
):
    role = Role(id=uuid.uuid4(), name="Super Admin", slug="super_admin", level=2, is_system=True, is_active=True)
    disabled = User(
        email="gone@example.com", username="gone", hashed_password="x",
        is_active=False, is_verified=True, role_id=role.id,
    )
    db_session.add_all([role, disabled])
    await db_session.commit()

    response = await async_client.put(
        f"{API}/admin/users/{disabled.id}{suffix}", json={"is_active": True}, headers=admin_headers
    )

    assert response.status_code == 403, response.text
