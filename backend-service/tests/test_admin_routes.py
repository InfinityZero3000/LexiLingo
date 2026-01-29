"""
Tests for Admin Routes
Testing admin CRUD operations for courses, units, lessons, vocabulary, achievements, and shop
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from uuid import uuid4

from app.models.course import Course, Unit, Lesson
from app.models.vocabulary import VocabularyItem
from app.models.gamification import Achievement, ShopItem
from app.models.user import User


class TestAdminCourses:
    """Tests for admin course CRUD"""
    
    @pytest.mark.asyncio
    async def test_create_course(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test creating a new course"""
        course_data = {
            "title": "Test Course",
            "description": "A test course",
            "language": "en",
            "level": "A1",
            "is_published": False
        }
        
        response = await async_client.post(
            "/api/v1/admin/courses",
            headers=auth_headers,
            json=course_data
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert data["data"]["title"] == "Test Course"
    
    @pytest.mark.asyncio
    async def test_update_course(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession
    ):
        """Test updating a course"""
        # Create test course
        course = Course(
            title="Original Title",
            description="Original description",
            language="en",
            level="A1",
            is_published=False
        )
        db_session.add(course)
        await db_session.commit()
        await db_session.refresh(course)
        
        update_data = {
            "title": "Updated Title",
            "is_published": True
        }
        
        response = await async_client.put(
            f"/api/v1/admin/courses/{course.id}",
            headers=auth_headers,
            json=update_data
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["title"] == "Updated Title"
    
    @pytest.mark.asyncio
    async def test_delete_course(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession
    ):
        """Test deleting a course"""
        course = Course(
            title="To Delete",
            description="Will be deleted",
            language="en",
            level="A1",
            is_published=True
        )
        db_session.add(course)
        await db_session.commit()
        await db_session.refresh(course)
        
        response = await async_client.delete(
            f"/api/v1/admin/courses/{course.id}",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["deleted"] is True


class TestAdminUnits:
    """Tests for admin unit CRUD"""
    
    @pytest.mark.asyncio
    async def test_create_unit(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession
    ):
        """Test creating a new unit"""
        # Create parent course first
        course = Course(
            title="Parent Course",
            description="For unit test",
            language="en",
            level="A1",
            is_published=True
        )
        db_session.add(course)
        await db_session.commit()
        await db_session.refresh(course)
        
        unit_data = {
            "title": "Test Unit",
            "description": "A test unit",
            "course_id": str(course.id),
            "order_index": 1
        }
        
        response = await async_client.post(
            "/api/v1/admin/units",
            headers=auth_headers,
            json=unit_data
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


class TestAdminLessons:
    """Tests for admin lesson CRUD"""
    
    @pytest.mark.asyncio
    async def test_create_lesson(
        self,
        async_client: AsyncClient,
        auth_headers: dict,
        db_session: AsyncSession
    ):
        """Test creating a new lesson"""
        # Create parent course and unit
        course = Course(
            title="Parent Course",
            description="For lesson test",
            language="en",
            level="A1",
            is_published=True
        )
        db_session.add(course)
        await db_session.commit()
        await db_session.refresh(course)
        
        unit = Unit(
            title="Parent Unit",
            description="For lesson test",
            course_id=course.id,
            order_index=1
        )
        db_session.add(unit)
        await db_session.commit()
        await db_session.refresh(unit)
        
        lesson_data = {
            "title": "Test Lesson",
            "unit_id": str(unit.id),
            "order_index": 1,
            "lesson_type": "vocabulary",
            "xp_reward": 10
        }
        
        response = await async_client.post(
            "/api/v1/admin/lessons",
            headers=auth_headers,
            json=lesson_data
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


class TestAdminVocabulary:
    """Tests for admin vocabulary CRUD"""
    
    @pytest.mark.asyncio
    async def test_list_vocabulary(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test listing vocabulary items"""
        response = await async_client.get(
            "/api/v1/admin/vocabulary",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_create_vocabulary(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test creating vocabulary item"""
        response = await async_client.post(
            "/api/v1/admin/vocabulary",
            headers=auth_headers,
            params={
                "word": "test",
                "translation": "thử nghiệm",
                "part_of_speech": "noun"
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


class TestAdminAchievements:
    """Tests for admin achievement CRUD"""
    
    @pytest.mark.asyncio
    async def test_list_achievements(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test listing achievements (admin)"""
        response = await async_client.get(
            "/api/v1/admin/achievements",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_create_achievement(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test creating an achievement"""
        response = await async_client.post(
            "/api/v1/admin/achievements",
            headers=auth_headers,
            params={
                "name": f"Test Achievement {uuid4().hex[:8]}",
                "description": "Test description",
                "condition_type": "test_condition",
                "condition_value": 1,
                "category": "test",
                "xp_reward": 10
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


class TestAdminShop:
    """Tests for admin shop CRUD"""
    
    @pytest.mark.asyncio
    async def test_list_shop_items(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test listing shop items (admin)"""
        response = await async_client.get(
            "/api/v1/admin/shop",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_create_shop_item(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test creating a shop item"""
        response = await async_client.post(
            "/api/v1/admin/shop",
            headers=auth_headers,
            params={
                "name": "Test Shop Item",
                "description": "Test item",
                "item_type": "test",
                "price_gems": 100
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True


class TestAdminSeed:
    """Tests for seed data endpoint"""
    
    @pytest.mark.asyncio
    async def test_seed_data(
        self,
        async_client: AsyncClient,
        auth_headers: dict
    ):
        """Test seeding sample data"""
        response = await async_client.post(
            "/api/v1/admin/seed",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "achievements" in data["data"]
        assert "shop_items" in data["data"]
