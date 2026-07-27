"""
Comprehensive Admin & Super Admin RBAC Security Tests
Tests role-based access control, privilege escalation prevention, and CRUD operations.

Usage:
    cd backend-service
    python -m pytest tests/test_admin_rbac_security.py -v
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from uuid import uuid4

from app.models.user import User
from app.models.rbac import Role
from app.models.course import Course
from app.models.gamification import Achievement, ShopItem
from app.core.security import create_access_token, get_password_hash


# ============================================================================
# Fixtures: Roles
# ============================================================================

@pytest.fixture
async def roles(db_session: AsyncSession):
    """Create the 3 system roles: user, admin, super_admin."""
    existing_roles = await db_session.execute(
        select(Role).where(Role.name.in_(["User", "Admin", "Super Admin"]))
    )
    by_name = {r.name: r for r in existing_roles.scalars().all()}

    if "User" not in by_name:
        db_session.add(
            Role(
                name="User", slug="user", level=0,
                description="Regular user", is_system=True, is_active=True
            )
        )
    else:
        by_name["User"].slug = "user"
        by_name["User"].level = 0
        by_name["User"].is_active = True

    if "Admin" not in by_name:
        db_session.add(
            Role(
                name="Admin", slug="admin", level=1,
                description="Admin user", is_system=True, is_active=True
            )
        )
    else:
        by_name["Admin"].slug = "admin"
        by_name["Admin"].level = 1
        by_name["Admin"].is_active = True

    if "Super Admin" not in by_name:
        db_session.add(
            Role(
                name="Super Admin", slug="super_admin", level=2,
                description="Super admin user", is_system=True, is_active=True
            )
        )
    else:
        by_name["Super Admin"].slug = "super_admin"
        by_name["Super Admin"].level = 2
        by_name["Super Admin"].is_active = True

    await db_session.commit()
    persisted_roles = await db_session.execute(
        select(Role).where(Role.name.in_(["User", "Admin", "Super Admin"]))
    )
    persisted_by_name = {r.name: r for r in persisted_roles.scalars().all()}
    return {
        "user": persisted_by_name["User"],
        "admin": persisted_by_name["Admin"],
        "super_admin": persisted_by_name["Super Admin"],
    }


# ============================================================================
# Fixtures: Users with different roles
# ============================================================================

@pytest.fixture
async def regular_user(db_session: AsyncSession, roles):
    """Create a regular user (level 0)."""
    existing = await db_session.execute(select(User).where(User.email == "regular@test.com"))
    user = existing.scalar_one_or_none()
    if user is None:
        user = User(
            id=uuid4(),
            email="regular@test.com",
            username="regular_user",
            hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
            display_name="Regular User",
            is_active=True,
            is_verified=True,
            role_id=roles["user"].id,
        )
        db_session.add(user)
    else:
        user.username = "regular_user"
        user.display_name = "Regular User"
        user.hashed_password = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu"
        user.is_active = True
        user.is_verified = True
        user.role_id = roles["user"].id
    await db_session.commit()
    return user


@pytest.fixture
async def admin_user(db_session: AsyncSession, roles):
    """Create an admin user (level 1)."""
    existing = await db_session.execute(select(User).where(User.email == "admin@test.com"))
    user = existing.scalar_one_or_none()
    if user is None:
        user = User(
            id=uuid4(),
            email="admin@test.com",
            username="admin_user",
            hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
            display_name="Admin User",
            is_active=True,
            is_verified=True,
            role_id=roles["admin"].id,
        )
        db_session.add(user)
    else:
        user.username = "admin_user"
        user.display_name = "Admin User"
        user.hashed_password = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu"
        user.is_active = True
        user.is_verified = True
        user.role_id = roles["admin"].id
    await db_session.commit()
    return user


@pytest.fixture
async def super_admin_user(db_session: AsyncSession, roles):
    """Create a super_admin user (level 2)."""
    existing = await db_session.execute(select(User).where(User.email == "superadmin@test.com"))
    user = existing.scalar_one_or_none()
    if user is None:
        user = User(
            id=uuid4(),
            email="superadmin@test.com",
            username="super_admin_user",
            hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
            display_name="Super Admin User",
            is_active=True,
            is_verified=True,
            role_id=roles["super_admin"].id,
        )
        db_session.add(user)
    else:
        user.username = "super_admin_user"
        user.display_name = "Super Admin User"
        user.hashed_password = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu"
        user.is_active = True
        user.is_verified = True
        user.role_id = roles["super_admin"].id
    await db_session.commit()
    return user


@pytest.fixture
async def another_admin_user(db_session: AsyncSession, roles):
    """Create a second admin user for cross-admin tests."""
    existing = await db_session.execute(select(User).where(User.email == "admin2@test.com"))
    user = existing.scalar_one_or_none()
    if user is None:
        user = User(
            id=uuid4(),
            email="admin2@test.com",
            username="admin_user_2",
            hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
            display_name="Admin User 2",
            is_active=True,
            is_verified=True,
            role_id=roles["admin"].id,
        )
        db_session.add(user)
    else:
        user.username = "admin_user_2"
        user.display_name = "Admin User 2"
        user.hashed_password = "$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu"
        user.is_active = True
        user.is_verified = True
        user.role_id = roles["admin"].id
    await db_session.commit()
    return user


# ============================================================================
# Fixtures: Auth headers
# ============================================================================

@pytest.fixture
def regular_headers(regular_user: User) -> dict:
    token = create_access_token(data={"sub": str(regular_user.id)})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def admin_headers(admin_user: User) -> dict:
    token = create_access_token(data={"sub": str(admin_user.id)})
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def super_admin_headers(super_admin_user: User) -> dict:
    token = create_access_token(data={"sub": str(super_admin_user.id)})
    return {"Authorization": f"Bearer {token}"}


# ============================================================================
# Test Suite 1: Access Control - Regular User Should Be Denied
# ============================================================================

class TestRegularUserDenied:
    """Regular users (level 0) should get 403 on all admin endpoints."""

    @pytest.mark.asyncio
    async def test_regular_user_cannot_list_admin_courses(self, async_client: AsyncClient, regular_headers):
        response = await async_client.get("/api/v1/admin/courses", headers=regular_headers)
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_regular_user_cannot_list_users(self, async_client: AsyncClient, regular_headers):
        response = await async_client.get("/api/v1/admin/users", headers=regular_headers)
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_regular_user_cannot_create_course(self, async_client: AsyncClient, regular_headers):
        response = await async_client.post("/api/v1/admin/courses", headers=regular_headers, json={
            "title": "Hacked Course", "description": "Should not exist",
            "language": "en", "level": "beginner"
        })
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_regular_user_cannot_access_rbac(self, async_client: AsyncClient, regular_headers):
        response = await async_client.get("/api/v1/admin/rbac/roles", headers=regular_headers)
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_regular_user_cannot_view_system_info(self, async_client: AsyncClient, regular_headers):
        response = await async_client.get("/api/v1/admin/system-info", headers=regular_headers)
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_regular_user_cannot_access_analytics(self, async_client: AsyncClient, regular_headers):
        response = await async_client.get("/api/v1/admin/analytics/dashboard/kpis", headers=regular_headers)
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_unauthenticated_user_denied(self, async_client: AsyncClient):
        response = await async_client.get("/api/v1/admin/courses")
        assert response.status_code in [401, 403]


# ============================================================================
# Test Suite 2: Admin Access - Should Be Allowed
# ============================================================================

class TestAdminAccess:
    """Admin users (level 1) should have access to admin endpoints."""

    @pytest.mark.asyncio
    async def test_admin_can_list_courses(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/courses", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_list_users(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/users", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_list_vocabulary(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/vocabulary", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_list_achievements(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/achievements", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_list_shop_items(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/shop", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_view_system_info(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/system-info", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_access_rbac_roles(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/rbac/roles", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_access_analytics_kpis(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get("/api/v1/admin/analytics/dashboard/kpis", headers=admin_headers)
        assert response.status_code == 200


# ============================================================================
# Test Suite 3: Super Admin Only Endpoints
# ============================================================================

class TestSuperAdminOnly:
    """Endpoints that require super_admin (level 2) should deny admin (level 1)."""

    @pytest.mark.asyncio
    async def test_admin_cannot_change_user_role(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Admin (level 1) should NOT be able to change user roles."""
        response = await async_client.put(
            f"/api/v1/admin/users/{regular_user.id}/role",
            headers=admin_headers,
            json={"level": 1}
        )
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_super_admin_can_change_user_role(
        self, async_client: AsyncClient, super_admin_headers, regular_user
    ):
        """Super admin (level 2) should be able to change user roles."""
        response = await async_client.put(
            f"/api/v1/admin/users/{regular_user.id}/role",
            headers=super_admin_headers,
            json={"level": 1}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["new_level"] == 1

    @pytest.mark.asyncio
    async def test_admin_cannot_assign_rbac_role(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Admin should NOT be able to use /rbac/users/assign-role."""
        response = await async_client.post(
            "/api/v1/admin/rbac/users/assign-role",
            headers=admin_headers,
            json={"user_id": str(regular_user.id), "role_slug": "admin"}
        )
        assert response.status_code == 403


# ============================================================================
# Test Suite 4: Privilege Escalation Prevention
# ============================================================================

class TestPrivilegeEscalation:
    """Ensure admins cannot escalate privileges or affect higher-level users."""

    @pytest.mark.asyncio
    async def test_admin_cannot_deactivate_super_admin(
        self, async_client: AsyncClient, admin_headers, super_admin_user
    ):
        """Admin (level 1) should NOT be able to deactivate super_admin (level 2)."""
        response = await async_client.put(
            f"/api/v1/admin/users/{super_admin_user.id}/status",
            headers=admin_headers,
            json={"is_active": False}
        )
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_admin_cannot_deactivate_another_admin(
        self, async_client: AsyncClient, admin_headers, another_admin_user
    ):
        """Admin (level 1) should NOT be able to deactivate another admin (level 1)."""
        response = await async_client.put(
            f"/api/v1/admin/users/{another_admin_user.id}/status",
            headers=admin_headers,
            json={"is_active": False}
        )
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_admin_can_deactivate_regular_user(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Admin (level 1) SHOULD be able to deactivate a regular user (level 0)."""
        response = await async_client.put(
            f"/api/v1/admin/users/{regular_user.id}/status",
            headers=admin_headers,
            json={"is_active": False}
        )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_super_admin_can_deactivate_admin(
        self, async_client: AsyncClient, super_admin_headers, admin_user
    ):
        """Super admin (level 2) SHOULD be able to deactivate admin (level 1)."""
        response = await async_client.put(
            f"/api/v1/admin/users/{admin_user.id}/status",
            headers=super_admin_headers,
            json={"is_active": False}
        )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_cannot_update_user_to_deactivate_super_admin(
        self, async_client: AsyncClient, admin_headers, super_admin_user
    ):
        """Admin should NOT be able to deactivate super_admin via update_user endpoint."""
        response = await async_client.put(
            f"/api/v1/admin/users/{super_admin_user.id}",
            headers=admin_headers,
            json={"is_active": False}
        )
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_admin_can_update_display_name_of_super_admin(
        self, async_client: AsyncClient, admin_headers, super_admin_user
    ):
        """Admin SHOULD be able to update non-sensitive fields (display_name) of any user."""
        response = await async_client.put(
            f"/api/v1/admin/users/{super_admin_user.id}",
            headers=admin_headers,
            json={"display_name": "New Name"}
        )
        # This should succeed because we only restrict is_active=False for higher roles
        assert response.status_code == 200


# ============================================================================
# Test Suite 5: Self-Action Prevention
# ============================================================================

class TestSelfActionPrevention:
    """Users should not be able to demote/deactivate themselves."""

    @pytest.mark.asyncio
    async def test_super_admin_cannot_demote_self(
        self, async_client: AsyncClient, super_admin_headers, super_admin_user
    ):
        """Super admin should NOT be able to demote themselves."""
        response = await async_client.put(
            f"/api/v1/admin/users/{super_admin_user.id}/role",
            headers=super_admin_headers,
            json={"level": 0}
        )
        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_admin_cannot_deactivate_self(
        self, async_client: AsyncClient, admin_headers, admin_user
    ):
        """Admin should NOT be able to deactivate themselves."""
        response = await async_client.put(
            f"/api/v1/admin/users/{admin_user.id}/status",
            headers=admin_headers,
            json={"is_active": False}
        )
        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_admin_cannot_bulk_deactivate_self(
        self, async_client: AsyncClient, admin_headers, admin_user
    ):
        """Admin should NOT be able to include themselves in bulk actions."""
        response = await async_client.post(
            "/api/v1/admin/users/bulk-action",
            headers=admin_headers,
            json={"user_ids": [str(admin_user.id)], "action": "deactivate"}
        )
        assert response.status_code == 400


# ============================================================================
# Test Suite 6: Content CRUD with Admin Auth
# ============================================================================

class TestContentCRUD:
    """Test content management CRUD operations with proper admin authentication."""

    @pytest.mark.asyncio
    async def test_create_course(self, async_client: AsyncClient, admin_headers):
        response = await async_client.post("/api/v1/admin/courses", headers=admin_headers, json={
            "title": "Test English Course",
            "description": "A comprehensive English course",
            "language": "en",
            "level": "A1",
            "is_published": True,
        })
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["data"]["title"] == "Test English Course"

    @pytest.mark.asyncio
    async def test_create_achievement(self, async_client: AsyncClient, admin_headers):
        response = await async_client.post("/api/v1/admin/achievements", headers=admin_headers, params={
            "name": "Test Achievement",
            "description": "A test achievement",
            "condition_type": "lessons_completed",
            "condition_value": 5,
            "category": "lessons",
            "rarity": "common",
            "xp_reward": 10,
            "gems_reward": 5,
        })
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True

    @pytest.mark.asyncio
    async def test_create_shop_item(self, async_client: AsyncClient, admin_headers):
        response = await async_client.post("/api/v1/admin/shop", headers=admin_headers, json={
            "name": "Test Item",
            "description": "A test item",
            "item_type": "streak_freeze",
            "price_gems": 100,
        })
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


# ============================================================================
# Test Suite 7: User Management Flows
# ============================================================================

class TestUserManagement:
    """Test user management workflows."""

    @pytest.mark.asyncio
    async def test_list_users_includes_all_roles(
        self, async_client: AsyncClient, admin_headers,
        regular_user, admin_user, super_admin_user
    ):
        """User list should include users from all roles."""
        response = await async_client.get("/api/v1/admin/users", headers=admin_headers)
        assert response.status_code == 200
        data = response.json()
        users_data = data["data"]["users"]
        emails = [u["email"] for u in users_data]
        assert "regular@test.com" in emails
        assert "admin@test.com" in emails
        assert "superadmin@test.com" in emails

    @pytest.mark.asyncio
    async def test_list_users_filter_by_role(
        self, async_client: AsyncClient, admin_headers, regular_user, admin_user
    ):
        """Should be able to filter users by role level."""
        response = await async_client.get(
            "/api/v1/admin/users?role=1", headers=admin_headers
        )
        assert response.status_code == 200
        data = response.json()
        users_data = data["data"]["users"]
        for u in users_data:
            assert u["role_level"] == 1

    @pytest.mark.asyncio
    async def test_list_users_search(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Should be able to search users by email."""
        response = await async_client.get(
            "/api/v1/admin/users?search=regular", headers=admin_headers
        )
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["total"] >= 1

    @pytest.mark.asyncio
    async def test_get_user_detail(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Should be able to get detailed user information."""
        response = await async_client.get(
            f"/api/v1/admin/users/{regular_user.id}",
            headers=admin_headers
        )
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["email"] == "regular@test.com"
        assert "courses_enrolled" in data["data"]
        assert "total_xp" in data["data"]

    @pytest.mark.asyncio
    async def test_update_user_display_name(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Admin should be able to update user display name."""
        response = await async_client.put(
            f"/api/v1/admin/users/{regular_user.id}",
            headers=admin_headers,
            json={"display_name": "Updated Name"}
        )
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["display_name"] == "Updated Name"

    @pytest.mark.asyncio
    async def test_get_nonexistent_user(self, async_client: AsyncClient, admin_headers):
        """Should return 404 for nonexistent user."""
        fake_uuid = str(uuid4())
        response = await async_client.get(
            f"/api/v1/admin/users/{fake_uuid}",
            headers=admin_headers
        )
        assert response.status_code == 404


# ============================================================================
# Test Suite 8: Bulk Operations with Role Checks
# ============================================================================

class TestBulkOperations:
    """Test bulk user operations with proper role checks."""

    @pytest.mark.asyncio
    async def test_admin_bulk_deactivate_regular_users(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Admin should be able to bulk deactivate regular users."""
        response = await async_client.post(
            "/api/v1/admin/users/bulk-action",
            headers=admin_headers,
            json={
                "user_ids": [str(regular_user.id)],
                "action": "deactivate"
            }
        )
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["updated_count"] == 1

    @pytest.mark.asyncio
    async def test_admin_bulk_cannot_deactivate_super_admin(
        self, async_client: AsyncClient, admin_headers, super_admin_user, regular_user
    ):
        """Admin bulk action should skip super_admin users (higher role level)."""
        response = await async_client.post(
            "/api/v1/admin/users/bulk-action",
            headers=admin_headers,
            json={
                "user_ids": [str(super_admin_user.id), str(regular_user.id)],
                "action": "deactivate"
            }
        )
        assert response.status_code == 200
        data = response.json()
        # Only the regular user should be deactivated, super_admin should be skipped
        assert data["data"]["updated_count"] == 1

    @pytest.mark.asyncio
    async def test_admin_bulk_delete_requires_super_admin(
        self, async_client: AsyncClient, admin_headers, regular_user
    ):
        """Bulk delete should require super_admin role."""
        response = await async_client.post(
            "/api/v1/admin/users/bulk-action",
            headers=admin_headers,
            json={
                "user_ids": [str(regular_user.id)],
                "action": "delete"
            }
        )
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_super_admin_bulk_delete(
        self, async_client: AsyncClient, super_admin_headers, regular_user
    ):
        """Super admin should be able to bulk delete regular users."""
        response = await async_client.post(
            "/api/v1/admin/users/bulk-action",
            headers=super_admin_headers,
            json={
                "user_ids": [str(regular_user.id)],
                "action": "delete"
            }
        )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_bulk_action_with_invalid_ids(
        self, async_client: AsyncClient, admin_headers
    ):
        """Bulk action with invalid UUID format should return 400."""
        response = await async_client.post(
            "/api/v1/admin/users/bulk-action",
            headers=admin_headers,
            json={
                "user_ids": ["not-a-valid-uuid"],
                "action": "activate"
            }
        )
        assert response.status_code == 400

    @pytest.mark.asyncio
    async def test_bulk_action_with_empty_ids(
        self, async_client: AsyncClient, admin_headers
    ):
        """Bulk action with no user IDs should return 400."""
        response = await async_client.post(
            "/api/v1/admin/users/bulk-action",
            headers=admin_headers,
            json={
                "user_ids": [],
                "action": "activate"
            }
        )
        assert response.status_code == 400


# ============================================================================
# Test Suite 9: RBAC Routes
# ============================================================================

class TestRBACRoutes:
    """Test RBAC management routes."""

    @pytest.mark.asyncio
    async def test_list_roles(self, async_client: AsyncClient, admin_headers, roles):
        response = await async_client.get("/api/v1/admin/rbac/roles", headers=admin_headers)
        assert response.status_code == 200
        data = response.json()
        slugs = [r["slug"] for r in data]
        assert "user" in slugs
        assert "admin" in slugs
        assert "super_admin" in slugs

    @pytest.mark.asyncio
    async def test_get_role_detail(self, async_client: AsyncClient, admin_headers, roles):
        response = await async_client.get("/api/v1/admin/rbac/roles/admin", headers=admin_headers)
        assert response.status_code == 200
        data = response.json()
        assert data["slug"] == "admin"
        assert data["level"] == 1

    @pytest.mark.asyncio
    async def test_list_permissions(self, async_client: AsyncClient, admin_headers, roles):
        response = await async_client.get("/api/v1/admin/rbac/permissions", headers=admin_headers)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_rbac_dashboard(self, async_client: AsyncClient, admin_headers, roles):
        response = await async_client.get("/api/v1/admin/rbac/dashboard", headers=admin_headers)
        assert response.status_code == 200
        data = response.json()
        assert "dashboard" in data

    @pytest.mark.asyncio
    async def test_rbac_deactivate_user_admin_cannot_deactivate_super_admin(
        self, async_client: AsyncClient, admin_headers, super_admin_user, roles
    ):
        """Admin should NOT be able to deactivate super_admin via RBAC endpoint."""
        response = await async_client.post(
            f"/api/v1/admin/rbac/users/{super_admin_user.id}/deactivate",
            headers=admin_headers
        )
        assert response.status_code == 403

    @pytest.mark.asyncio
    async def test_rbac_deactivate_regular_user(
        self, async_client: AsyncClient, admin_headers, regular_user, roles
    ):
        """Admin SHOULD be able to deactivate regular user via RBAC endpoint."""
        response = await async_client.post(
            f"/api/v1/admin/rbac/users/{regular_user.id}/deactivate",
            headers=admin_headers
        )
        assert response.status_code == 200


# ============================================================================
# Test Suite 10: Analytics Access Control
# ============================================================================

class TestAnalyticsAccess:
    """Test analytics endpoints are properly protected."""

    @pytest.mark.asyncio
    async def test_admin_can_view_kpis(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get(
            "/api/v1/admin/analytics/dashboard/kpis", headers=admin_headers
        )
        assert response.status_code == 200
        data = response.json()
        assert "kpis" in data

    @pytest.mark.asyncio
    async def test_admin_can_view_user_growth(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get(
            "/api/v1/admin/analytics/dashboard/user-growth", headers=admin_headers
        )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_admin_can_view_engagement(self, async_client: AsyncClient, admin_headers):
        response = await async_client.get(
            "/api/v1/admin/analytics/dashboard/engagement", headers=admin_headers
        )
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_regular_user_cannot_view_analytics(self, async_client: AsyncClient, regular_headers):
        response = await async_client.get(
            "/api/v1/admin/analytics/dashboard/kpis", headers=regular_headers
        )
        assert response.status_code == 403
