"""
Tests for Admin Routes
Testing admin CRUD operations for courses, units, lessons, vocabulary, achievements, and shop
"""

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from unittest.mock import MagicMock, patch
from uuid import uuid4

from app.models.course import Course, Unit, Lesson
from app.models.vocabulary import VocabularyItem
from app.models.gamification import Achievement, ShopItem
from app.models.user import User
from app.models.content import GrammarItem, QuestionItem, TestExam


class TestAdminCourses:
    """Tests for admin course CRUD"""
    
    @pytest.mark.asyncio
    async def test_create_course(
        self,
        async_client: AsyncClient,
        admin_headers: dict
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
            headers=admin_headers,
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
        admin_headers: dict,
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
            headers=admin_headers,
            json=update_data
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["data"]["title"] == "Updated Title"
    
    @pytest.mark.asyncio
    async def test_delete_course(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
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
            headers=admin_headers
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
        admin_headers: dict,
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
            headers=admin_headers,
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
        admin_headers: dict,
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
            "lesson_type": "lesson",
            "xp_reward": 10
        }
        
        response = await async_client.post(
            "/api/v1/admin/lessons",
            headers=admin_headers,
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
        admin_headers: dict
    ):
        """Test listing vocabulary items"""
        response = await async_client.get(
            "/api/v1/admin/vocabulary",
            headers=admin_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_create_vocabulary(
        self,
        async_client: AsyncClient,
        admin_headers: dict
    ):
        """Test creating vocabulary item"""
        response = await async_client.post(
            "/api/v1/admin/vocabulary",
            headers=admin_headers,
            params={
                "word": "test",
                "definition": "a test word",
                "translation": "thử nghiệm",
                "part_of_speech": "noun"
            }
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True

    @pytest.mark.asyncio
    async def test_bulk_import_vocabulary_from_pdf(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
    ):
        csv_text = "word,definition,translation\npdfword,From PDF,Từ PDF"
        with patch("app.routes.admin_courses._extract_pdf_text", return_value=csv_text):
            response = await async_client.post(
                "/api/v1/admin/vocabulary/bulk-import",
                headers=admin_headers,
                files={"file": ("vocabulary.pdf", b"pdf", "application/pdf")},
            )

        assert response.status_code == 200
        assert response.json()["data"]["created"] == 1

    def test_extract_pdf_text_joins_pages(self):
        from app.routes.admin_courses import _extract_pdf_text

        pages = [MagicMock(), MagicMock()]
        pages[0].extract_text.return_value = "page one"
        pages[1].extract_text.return_value = "page two"
        with patch("app.routes.admin_courses.PdfReader") as reader:
            reader.return_value.pages = pages
            assert _extract_pdf_text(b"pdf") == "page one\npage two"

    @pytest.mark.asyncio
    async def test_extract_pdf_text(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
    ):
        with patch("app.routes.admin_courses._extract_pdf_text", return_value="# PDF Course"):
            response = await async_client.post(
                "/api/v1/admin/import/extract-pdf-text",
                headers=admin_headers,
                files={"file": ("course.pdf", b"pdf", "application/pdf")},
            )

        assert response.status_code == 200
        assert response.json()["data"] == {"text": "# PDF Course"}

    @pytest.mark.asyncio
    async def test_extract_pdf_text_rejects_non_pdf(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
    ):
        response = await async_client.post(
            "/api/v1/admin/import/extract-pdf-text",
            headers=admin_headers,
            files={"file": ("course.txt", b"text", "text/plain")},
        )

        assert response.status_code == 400
        assert response.json()["error"]["message"] == "Only PDF files are supported"


class TestAdminContentLab:
    """Tests for admin-managed grammar, question bank, and test exams."""

    @pytest.mark.asyncio
    async def test_list_content_lab_handles_legacy_json_shapes(
        self,
        async_client: AsyncClient,
        admin_headers: dict,
        db_session: AsyncSession,
    ):
        """Legacy rows should not make content-lab list endpoints return 500."""
        grammar = GrammarItem(
            title="Legacy Grammar",
            level="A1",
            topic="basics",
            summary="Legacy JSON shapes",
            content="Use the verb to be for identity and state.",
            examples={"sentence": "I am a student."},
            tags={"grammar": True, "level": "beginner"},
            is_active=True,
        )
        db_session.add(grammar)
        await db_session.commit()
        await db_session.refresh(grammar)

        question = QuestionItem(
            prompt="Choose the correct answer.",
            question_type="mcq",
            options={"items": ["am", "is", "are"]},
            answer={"value": "am"},
            explanation="Use am with I.",
            difficulty_level="A1",
            tags={"grammar": True},
            grammar_id=grammar.id,
            is_active=True,
        )
        db_session.add(question)
        await db_session.commit()
        await db_session.refresh(question)

        test_exam = TestExam(
            title="Placement A1",
            description="A short test",
            level="A1",
            duration_minutes=15,
            passing_score=70,
            question_ids=[str(question.id)],
            is_published=False,
        )
        db_session.add(test_exam)
        await db_session.commit()

        grammar_response = await async_client.get(
            "/api/v1/admin/grammar",
            headers=admin_headers,
        )
        questions_response = await async_client.get(
            "/api/v1/admin/questions",
            headers=admin_headers,
        )
        tests_response = await async_client.get(
            "/api/v1/admin/test-exams",
            headers=admin_headers,
        )

        assert grammar_response.status_code == 200
        assert questions_response.status_code == 200
        assert tests_response.status_code == 200

        grammar_data = grammar_response.json()["data"][0]
        question_data = questions_response.json()["data"][0]
        test_data = tests_response.json()["data"][0]

        assert grammar_data["examples"] == [{"sentence": "I am a student."}]
        assert set(grammar_data["tags"]) == {"grammar", "beginner"}
        assert question_data["options"] == [{"items": ["am", "is", "are"]}]
        assert question_data["tags"] == ["grammar"]
        assert test_data["question_ids"] == [str(question.id)]


class TestAdminAchievements:
    """Tests for admin achievement CRUD"""
    
    @pytest.mark.asyncio
    async def test_list_achievements(
        self,
        async_client: AsyncClient,
        admin_headers: dict
    ):
        """Test listing achievements (admin)"""
        response = await async_client.get(
            "/api/v1/admin/achievements",
            headers=admin_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_create_achievement(
        self,
        async_client: AsyncClient,
        admin_headers: dict
    ):
        """Test creating an achievement"""
        response = await async_client.post(
            "/api/v1/admin/achievements",
            headers=admin_headers,
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
        admin_headers: dict
    ):
        """Test listing shop items (admin)"""
        response = await async_client.get(
            "/api/v1/admin/shop",
            headers=admin_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert isinstance(data["data"], list)
    
    @pytest.mark.asyncio
    async def test_create_shop_item(
        self,
        async_client: AsyncClient,
        admin_headers: dict
    ):
        """Test creating a shop item"""
        response = await async_client.post(
            "/api/v1/admin/shop",
            headers=admin_headers,
            json={
                "name": "Test Shop Item",
                "description": "Test item",
                "item_type": "test",
                "price_gems": 100
            }
        )

        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True

    @pytest.mark.asyncio
    async def test_create_shop_item_persists_effects_and_icon_url(
        self,
        async_client: AsyncClient,
        admin_headers: dict
    ):
        """effects/icon_url must round-trip — admin-created power-ups need a real effects payload to work in-game"""
        response = await async_client.post(
            "/api/v1/admin/shop",
            headers=admin_headers,
            json={
                "name": "Test Time Freeze",
                "description": "Pauses the timer",
                "item_type": "time_freeze",
                "price_gems": 10,
                "icon_url": "assets/icon-library/clock_freeze.png",
                "effects": {"seconds": 15},
            }
        )

        assert response.status_code == 200
        item_id = response.json()["data"]["id"]

        list_response = await async_client.get(
            "/api/v1/admin/shop?include_unavailable=true",
            headers=admin_headers
        )
        created = next(
            item for item in list_response.json()["data"] if item["id"] == item_id
        )
        assert created["effects"] == {"seconds": 15}
        assert created["icon_url"] == "assets/icon-library/clock_freeze.png"

    @pytest.mark.asyncio
    async def test_update_shop_item_can_change_effects(
        self,
        async_client: AsyncClient,
        admin_headers: dict
    ):
        """Admin must be able to retune an existing power-up's effects payload"""
        create_response = await async_client.post(
            "/api/v1/admin/shop",
            headers=admin_headers,
            json={
                "name": "Test Lucky Clover",
                "description": "30% auto-correct chance",
                "item_type": "lucky_clover",
                "price_gems": 20,
                "effects": {"chance": 0.3},
            }
        )
        item_id = create_response.json()["data"]["id"]

        update_response = await async_client.put(
            f"/api/v1/admin/shop/{item_id}",
            headers=admin_headers,
            json={"effects": {"chance": 0.5}}
        )
        assert update_response.status_code == 200

        list_response = await async_client.get(
            "/api/v1/admin/shop?include_unavailable=true",
            headers=admin_headers
        )
        updated = next(
            item for item in list_response.json()["data"] if item["id"] == item_id
        )
        assert updated["effects"] == {"chance": 0.5}


class TestAdminSeed:
    """Tests for seed data endpoint"""
    
    @pytest.mark.asyncio
    async def test_seed_data(
        self,
        async_client: AsyncClient,
        admin_headers: dict
    ):
        """Test seeding sample data"""
        response = await async_client.post(
            "/api/v1/admin/seed",
            headers=admin_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["success"] is True
        assert "achievements" in data["data"]
        assert "shop_items" in data["data"]
