"""
Tests for Course Category API Routes
/Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/routes/course_categories.py

Note: router is registered at /api/v1/categories (not /course-categories).

Covers:
- GET  /api/v1/categories                   — list all categories (public)
- GET  /api/v1/categories/{id}              — get by id (public)
- GET  /api/v1/categories/slug/{slug}       — get by slug (public)
- GET  /api/v1/categories/{id}/courses      — courses in category (public)
- POST /api/v1/categories                   — create (auth required)
- PUT  /api/v1/categories/{id}              — update (auth required)
- DELETE /api/v1/categories/{id}            — delete (auth required)
- POST /api/v1/categories/update-counts     — update course counts (auth required)
"""

import pytest
import uuid
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch
from httpx import AsyncClient, ASGITransport

BASE = "/api/v1/categories"
CATEGORY_ID = "00000000-0000-0000-0000-000000000020"


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture
async def auth_client():
    from app.main import app
    from app.core.database import get_db
    from app.core.dependencies import get_current_user, get_current_admin

    mock_result = MagicMock()
    mock_result.scalar.return_value = None
    mock_result.scalar_one_or_none.return_value = None
    mock_result.scalars.return_value.all.return_value = []
    mock_result.all.return_value = []
    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    mock_session.execute = fake_execute
    mock_session.add = MagicMock()
    mock_session.commit = AsyncMock()
    mock_session.flush = AsyncMock()
    mock_session.refresh = AsyncMock()

    mock_user = MagicMock()
    mock_user.id = "00000000-0000-0000-0000-000000000001"
    mock_user.username = "testuser"
    mock_user.email = "test@example.com"
    mock_user.is_active = True
    mock_user.is_verified = True
    mock_user.level = "beginner"
    mock_user.native_language = "vi"
    mock_user.target_language = "en"
    mock_user.total_xp = 100
    mock_user.display_name = "Test User"

    async def mock_get_db():
        yield mock_session

    async def mock_get_current_user():
        return mock_user

    async def mock_get_current_admin():
        return mock_user

    app.dependency_overrides[get_db] = mock_get_db
    app.dependency_overrides[get_current_user] = mock_get_current_user
    app.dependency_overrides[get_current_admin] = mock_get_current_admin

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    app.dependency_overrides.clear()


@pytest.fixture
async def no_auth_client():
    from app.main import app
    from app.core.database import get_db

    mock_result = MagicMock()
    mock_result.scalar.return_value = None
    mock_result.scalar_one_or_none.return_value = None
    mock_result.scalars.return_value.all.return_value = []
    mock_result.all.return_value = []
    mock_session = MagicMock()

    async def fake_execute(query):
        return mock_result

    mock_session.execute = fake_execute

    async def mock_get_db():
        yield mock_session

    app.dependency_overrides[get_db] = mock_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


def _make_mock_category(
    category_id: str = CATEGORY_ID,
    name: str = "Grammar",
    slug: str = "grammar",
):
    """Build a mock category object with sensible defaults."""
    cat = MagicMock()
    cat.id = uuid.UUID(category_id)
    cat.name = name
    cat.slug = slug
    cat.description = "Grammar lessons"
    cat.icon = "📚"
    cat.color = "#2196F3"
    cat.order_index = 0
    cat.is_active = True
    cat.course_count = 5
    cat.created_at = datetime.utcnow()
    cat.updated_at = datetime.utcnow()
    return cat


# ============================================================================
# GET /api/v1/categories  — List all
# ============================================================================

class TestListCategories:
    """Tests for GET /api/v1/categories."""

    @pytest.mark.asyncio
    async def test_returns_200(self, no_auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_all_categories",
            new=AsyncMock(return_value=([], 0)),
        ):
            response = await no_auth_client.get(BASE)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_response_has_data_key(self, no_auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_all_categories",
            new=AsyncMock(return_value=([], 0)),
        ):
            response = await no_auth_client.get(BASE)
        assert "data" in response.json()

    @pytest.mark.asyncio
    async def test_returns_category_items(self, no_auth_client: AsyncClient):
        cat = _make_mock_category()
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_all_categories",
            new=AsyncMock(return_value=([cat], 1)),
        ):
            response = await no_auth_client.get(BASE)
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_active_only_default_is_true(self, no_auth_client: AsyncClient):
        mock_get_all = AsyncMock(return_value=([], 0))
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_all_categories",
            new=mock_get_all,
        ):
            await no_auth_client.get(BASE)
        _, call_kwargs = mock_get_all.call_args
        assert call_kwargs["active_only"] is True

    @pytest.mark.asyncio
    async def test_active_only_false_is_passed_through(self, no_auth_client: AsyncClient):
        mock_get_all = AsyncMock(return_value=([], 0))
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_all_categories",
            new=mock_get_all,
        ):
            await no_auth_client.get(f"{BASE}?active_only=false")
        _, call_kwargs = mock_get_all.call_args
        assert call_kwargs["active_only"] is False


# ============================================================================
# GET /api/v1/categories/{id}  — Get by ID
# ============================================================================

class TestGetCategoryById:
    """Tests for GET /api/v1/categories/{id}."""

    @pytest.mark.asyncio
    async def test_returns_404_when_not_found(self, no_auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_id",
            new=AsyncMock(return_value=None),
        ):
            response = await no_auth_client.get(f"{BASE}/{CATEGORY_ID}")
        assert response.status_code == 404
        assert "not found" in response.json()["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_returns_200_when_found(self, no_auth_client: AsyncClient):
        cat = _make_mock_category()
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_id",
            new=AsyncMock(return_value=cat),
        ):
            response = await no_auth_client.get(f"{BASE}/{CATEGORY_ID}")
        assert response.status_code == 200

    @pytest.mark.asyncio
    async def test_invalid_uuid_returns_422(self, no_auth_client: AsyncClient):
        response = await no_auth_client.get(f"{BASE}/not-a-uuid")
        assert response.status_code == 422


# ============================================================================
# GET /api/v1/categories/slug/{slug}  — Get by slug
# ============================================================================

class TestGetCategoryBySlug:
    """Tests for GET /api/v1/categories/slug/{slug}."""

    @pytest.mark.asyncio
    async def test_returns_404_when_slug_not_found(self, no_auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_slug",
            new=AsyncMock(return_value=None),
        ):
            response = await no_auth_client.get(f"{BASE}/slug/nonexistent-slug")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_returns_200_when_slug_found(self, no_auth_client: AsyncClient):
        cat = _make_mock_category()
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_slug",
            new=AsyncMock(return_value=cat),
        ):
            response = await no_auth_client.get(f"{BASE}/slug/grammar")
        assert response.status_code == 200


# ============================================================================
# GET /api/v1/categories/{id}/courses  — Courses in category
# ============================================================================

class TestGetCoursesByCategory:
    """Tests for GET /api/v1/categories/{id}/courses."""

    @pytest.mark.asyncio
    async def test_returns_404_when_category_not_found(self, no_auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_id",
            new=AsyncMock(return_value=None),
        ):
            response = await no_auth_client.get(f"{BASE}/{CATEGORY_ID}/courses")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_returns_200_with_empty_courses(self, no_auth_client: AsyncClient):
        cat = _make_mock_category()
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_id",
            new=AsyncMock(return_value=cat),
        ), patch(
            "app.crud.course_category.CourseCategoryCRUD.get_courses_by_category",
            new=AsyncMock(return_value=([], 0)),
        ):
            response = await no_auth_client.get(f"{BASE}/{CATEGORY_ID}/courses")
        assert response.status_code == 200
        data = response.json()
        assert "data" in data
        assert data["data"] == []

    @pytest.mark.asyncio
    async def test_pagination_meta_present(self, no_auth_client: AsyncClient):
        cat = _make_mock_category()
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_id",
            new=AsyncMock(return_value=cat),
        ), patch(
            "app.crud.course_category.CourseCategoryCRUD.get_courses_by_category",
            new=AsyncMock(return_value=([], 0)),
        ):
            response = await no_auth_client.get(f"{BASE}/{CATEGORY_ID}/courses")
        assert "pagination" in response.json()


# ============================================================================
# POST /api/v1/categories  — Create (auth required)
# ============================================================================

class TestCreateCategory:
    """Tests for POST /api/v1/categories."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        payload = {"name": "Vocabulary", "slug": "vocabulary"}
        response = await no_auth_client.post(BASE, json=payload)
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_400_if_slug_already_exists(self, auth_client: AsyncClient):
        existing = _make_mock_category()
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_slug",
            new=AsyncMock(return_value=existing),
        ):
            response = await auth_client.post(
                BASE,
                json={"name": "Grammar", "slug": "grammar"},
            )
        assert response.status_code == 400
        assert "slug" in response.json()["error"]["message"].lower()

    @pytest.mark.asyncio
    async def test_creates_category_successfully(self, auth_client: AsyncClient):
        new_cat = _make_mock_category()
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_slug",
            new=AsyncMock(return_value=None),
        ), patch(
            "app.crud.course_category.CourseCategoryCRUD.create_category",
            new=AsyncMock(return_value=new_cat),
        ):
            response = await auth_client.post(
                BASE,
                json={"name": "Grammar", "slug": "grammar"},
            )
        assert response.status_code == 201

    @pytest.mark.asyncio
    async def test_missing_required_fields_returns_422(self, auth_client: AsyncClient):
        response = await auth_client.post(BASE, json={})
        assert response.status_code == 422


# ============================================================================
# PUT /api/v1/categories/{id}  — Update (auth required)
# ============================================================================

class TestUpdateCategory:
    """Tests for PUT /api/v1/categories/{id}."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.put(f"{BASE}/{CATEGORY_ID}", json={"name": "New Name"})
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_category_not_found(self, auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_slug",
            new=AsyncMock(return_value=None),
        ), patch(
            "app.crud.course_category.CourseCategoryCRUD.update_category",
            new=AsyncMock(return_value=None),
        ):
            response = await auth_client.put(
                f"{BASE}/{CATEGORY_ID}", json={"name": "Updated"}
            )
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_updates_successfully(self, auth_client: AsyncClient):
        updated_cat = _make_mock_category(name="Updated Grammar")
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.get_category_by_slug",
            new=AsyncMock(return_value=None),
        ), patch(
            "app.crud.course_category.CourseCategoryCRUD.update_category",
            new=AsyncMock(return_value=updated_cat),
        ):
            response = await auth_client.put(
                f"{BASE}/{CATEGORY_ID}", json={"name": "Updated Grammar"}
            )
        assert response.status_code == 200


# ============================================================================
# DELETE /api/v1/categories/{id}  — Delete (auth required)
# ============================================================================

class TestDeleteCategory:
    """Tests for DELETE /api/v1/categories/{id}."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.delete(f"{BASE}/{CATEGORY_ID}")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_404_when_not_found(self, auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.delete_category",
            new=AsyncMock(return_value=False),
        ):
            response = await auth_client.delete(f"{BASE}/{CATEGORY_ID}")
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_deletes_successfully(self, auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.delete_category",
            new=AsyncMock(return_value=True),
        ):
            response = await auth_client.delete(f"{BASE}/{CATEGORY_ID}")
        assert response.status_code == 200
        assert response.json()["data"]["id"] == CATEGORY_ID


# ============================================================================
# POST /api/v1/categories/update-counts  — Update course counts (auth required)
# ============================================================================

class TestUpdateCourseCounts:
    """Tests for POST /api/v1/categories/update-counts."""

    @pytest.mark.asyncio
    async def test_requires_auth(self, no_auth_client: AsyncClient):
        response = await no_auth_client.post(f"{BASE}/update-counts")
        assert response.status_code == 401

    @pytest.mark.asyncio
    async def test_returns_200_on_success(self, auth_client: AsyncClient):
        with patch(
            "app.crud.course_category.CourseCategoryCRUD.update_course_counts",
            new=AsyncMock(return_value=None),
        ):
            response = await auth_client.post(f"{BASE}/update-counts")
        assert response.status_code == 200
        assert response.json()["data"]["status"] == "completed"
