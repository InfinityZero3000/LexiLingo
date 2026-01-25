"""
Tests for Progress Tracking API endpoints
"""
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.course import Course, Unit, Lesson
from app.models.progress import UserCourseProgress, LessonCompletion
from app.models.user import User


@pytest.mark.asyncio
async def test_get_my_progress_empty(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
):
    """Test GET /progress/me with no progress data"""
    response = await async_client.get("/api/v1/progress/me")
    
    assert response.status_code == 200
    data = response.json()
    
    assert "summary" in data
    assert data["summary"]["total_xp"] == 0
    assert data["summary"]["courses_enrolled"] == 0
    assert data["summary"]["courses_completed"] == 0
    assert data["summary"]["lessons_completed"] == 0
    
    assert "course_progress" in data
    assert isinstance(data["course_progress"], list)
    assert len(data["course_progress"]) == 0


@pytest.mark.asyncio
async def test_get_my_progress_with_data(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test GET /progress/me with existing progress"""
    # Create progress
    progress = UserCourseProgress(
        user_id=authenticated_user.id,
        course_id=sample_course.id,
        progress_percentage=50.0,
        total_xp_earned=100,
        lessons_completed=5,
    )
    db_session.add(progress)
    await db_session.commit()
    
    response = await async_client.get("/api/v1/progress/me")
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["summary"]["total_xp"] == 100
    assert data["summary"]["courses_enrolled"] == 1
    assert data["summary"]["lessons_completed"] == 5
    
    assert len(data["course_progress"]) == 1
    course_prog = data["course_progress"][0]
    assert course_prog["course_id"] == str(sample_course.id)
    assert course_prog["progress_percentage"] == 50.0
    assert course_prog["total_xp_earned"] == 100


@pytest.mark.asyncio
async def test_get_course_progress_not_enrolled(
    async_client: AsyncClient,
    authenticated_user: User,
    sample_course: Course,
):
    """Test GET /progress/courses/{id} when not enrolled"""
    response = await async_client.get(f"/api/v1/progress/courses/{sample_course.id}")
    
    assert response.status_code == 403
    assert "not enrolled" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_get_course_progress_with_units(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test GET /progress/courses/{id} with units breakdown"""
    # Enroll user
    from app.crud.course import CourseCRUD
    await CourseCRUD.enroll_user(db_session, authenticated_user.id, sample_course.id)
    
    # Create units and lessons
    unit1 = Unit(
        course_id=sample_course.id,
        title="Unit 1",
        description="Test unit",
        order_index=1,
    )
    db_session.add(unit1)
    await db_session.commit()
    await db_session.refresh(unit1)
    
    lesson1 = Lesson(
        unit_id=unit1.id,
        title="Lesson 1",
        description="Test lesson",
        order_index=1,
        content={"type": "vocabulary"},
    )
    lesson2 = Lesson(
        unit_id=unit1.id,
        title="Lesson 2",
        description="Test lesson",
        order_index=2,
        content={"type": "grammar"},
    )
    db_session.add_all([lesson1, lesson2])
    await db_session.commit()
    await db_session.refresh(lesson1)
    
    # Complete one lesson
    completion = LessonCompletion(
        user_id=authenticated_user.id,
        lesson_id=lesson1.id,
        is_passed=True,
        score=85.0,
        best_score=85.0,
    )
    db_session.add(completion)
    await db_session.commit()
    
    response = await async_client.get(f"/api/v1/progress/courses/{sample_course.id}")
    
    assert response.status_code == 200
    data = response.json()
    
    assert "course" in data
    assert "units_progress" in data
    
    assert len(data["units_progress"]) == 1
    unit_prog = data["units_progress"][0]
    assert unit_prog["unit_id"] == str(unit1.id)
    assert unit_prog["total_lessons"] == 2
    assert unit_prog["completed_lessons"] == 1
    assert unit_prog["progress_percentage"] == 50.0


@pytest.mark.asyncio
async def test_complete_lesson_first_time_pass(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test POST /progress/lessons/{id}/complete - First pass awards XP"""
    # Enroll and create lesson
    from app.crud.course import CourseCRUD
    await CourseCRUD.enroll_user(db_session, authenticated_user.id, sample_course.id)
    
    unit = Unit(
        course_id=sample_course.id,
        title="Unit 1",
        description="Test",
        order_index=1,
    )
    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)
    
    lesson = Lesson(
        unit_id=unit.id,
        title="Lesson 1",
        description="Test",
        order_index=1,
        content={"type": "vocab"},
        xp_reward=20,
    )
    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)
    
    response = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 85.0},
    )
    
    assert response.status_code == 200
    data = response.json()
    
    assert data["is_passed"] is True
    assert data["score"] == 85.0
    assert data["best_score"] == 85.0
    assert data["xp_earned"] == 20
    assert data["total_xp"] == 20
    assert "congratulations" in data["message"].lower()


@pytest.mark.asyncio
async def test_complete_lesson_idempotent(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test POST /progress/lessons/{id}/complete - Idempotent (no duplicate XP)"""
    # Setup
    from app.crud.course import CourseCRUD
    await CourseCRUD.enroll_user(db_session, authenticated_user.id, sample_course.id)
    
    unit = Unit(
        course_id=sample_course.id,
        title="Unit 1",
        description="Test",
        order_index=1,
    )
    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)
    
    lesson = Lesson(
        unit_id=unit.id,
        title="Lesson 1",
        description="Test",
        order_index=1,
        content={"type": "vocab"},
        xp_reward=20,
    )
    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)
    
    # First completion (pass)
    response1 = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 85.0},
    )
    assert response1.status_code == 200
    assert response1.json()["xp_earned"] == 20
    
    # Second completion (same score) - No XP
    response2 = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 85.0},
    )
    assert response2.status_code == 200
    data2 = response2.json()
    assert data2["xp_earned"] == 0
    assert data2["total_xp"] == 20  # Still 20, not 40
    assert "already completed" in data2["message"].lower()


@pytest.mark.asyncio
async def test_complete_lesson_improve_score(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test POST /progress/lessons/{id}/complete - Better score updates best_score"""
    # Setup
    from app.crud.course import CourseCRUD
    await CourseCRUD.enroll_user(db_session, authenticated_user.id, sample_course.id)
    
    unit = Unit(
        course_id=sample_course.id,
        title="Unit 1",
        description="Test",
        order_index=1,
    )
    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)
    
    lesson = Lesson(
        unit_id=unit.id,
        title="Lesson 1",
        description="Test",
        order_index=1,
        content={"type": "vocab"},
        xp_reward=20,
    )
    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)
    
    # First: score 80
    response1 = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 80.0},
    )
    assert response1.json()["best_score"] == 80.0
    assert response1.json()["xp_earned"] == 20
    
    # Second: score 95 (better)
    response2 = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 95.0},
    )
    data2 = response2.json()
    assert data2["best_score"] == 95.0
    assert data2["xp_earned"] == 0  # No additional XP
    assert "improved" in data2["message"].lower()


@pytest.mark.asyncio
async def test_complete_lesson_fail_then_pass(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test POST /progress/lessons/{id}/complete - Fail then pass awards XP"""
    # Setup
    from app.crud.course import CourseCRUD
    await CourseCRUD.enroll_user(db_session, authenticated_user.id, sample_course.id)
    
    unit = Unit(
        course_id=sample_course.id,
        title="Unit 1",
        description="Test",
        order_index=1,
    )
    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)
    
    lesson = Lesson(
        unit_id=unit.id,
        title="Lesson 1",
        description="Test",
        order_index=1,
        content={"type": "vocab"},
        xp_reward=20,
    )
    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)
    
    # First: Fail (score < 80)
    response1 = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 70.0},
    )
    data1 = response1.json()
    assert data1["is_passed"] is False
    assert data1["xp_earned"] == 0
    
    # Second: Pass (score >= 80)
    response2 = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 85.0},
    )
    data2 = response2.json()
    assert data2["is_passed"] is True
    assert data2["xp_earned"] == 20  # Now awards XP!
    assert data2["total_xp"] == 20


@pytest.mark.asyncio
async def test_get_total_xp(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test GET /progress/xp"""
    # Create progress with XP
    progress = UserCourseProgress(
        user_id=authenticated_user.id,
        course_id=sample_course.id,
        progress_percentage=30.0,
        total_xp_earned=150,
        lessons_completed=3,
    )
    db_session.add(progress)
    await db_session.commit()
    
    response = await async_client.get("/api/v1/progress/xp")
    
    assert response.status_code == 200
    data = response.json()
    assert data["total_xp"] == 150


@pytest.mark.asyncio
async def test_complete_lesson_not_enrolled(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test POST /progress/lessons/{id}/complete when not enrolled"""
    unit = Unit(
        course_id=sample_course.id,
        title="Unit 1",
        description="Test",
        order_index=1,
    )
    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)
    
    lesson = Lesson(
        unit_id=unit.id,
        title="Lesson 1",
        description="Test",
        order_index=1,
        content={"type": "vocab"},
    )
    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)
    
    response = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 85.0},
    )
    
    assert response.status_code == 403
    assert "not enrolled" in response.json()["detail"].lower()


@pytest.mark.asyncio
async def test_complete_lesson_invalid_score(
    async_client: AsyncClient,
    authenticated_user: User,
    db_session: AsyncSession,
    sample_course: Course,
):
    """Test POST /progress/lessons/{id}/complete with invalid score"""
    from app.crud.course import CourseCRUD
    await CourseCRUD.enroll_user(db_session, authenticated_user.id, sample_course.id)
    
    unit = Unit(
        course_id=sample_course.id,
        title="Unit 1",
        description="Test",
        order_index=1,
    )
    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)
    
    lesson = Lesson(
        unit_id=unit.id,
        title="Lesson 1",
        description="Test",
        order_index=1,
        content={"type": "vocab"},
    )
    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)
    
    # Score > 100
    response = await async_client.post(
        f"/api/v1/progress/lessons/{lesson.id}/complete",
        json={"lesson_id": str(lesson.id), "score": 150.0},
    )
    assert response.status_code == 422  # Validation error
