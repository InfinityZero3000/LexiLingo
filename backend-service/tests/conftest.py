"""
Pytest Configuration and Fixtures
Shared test fixtures for backend API tests
"""

import pytest
import asyncio
from typing import AsyncGenerator
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.pool import NullPool
from uuid import uuid4

from app.main import app
from app.core.database import Base, get_db
from app.core.security import create_access_token, get_password_hash
from app.models.user import User
from app.models.course import Course, Unit, Lesson
from app.models.progress import LessonAttempt, UserProgress, Streak
from app.models.vocabulary import VocabularyItem


# Test database URL (use separate test database)
TEST_DATABASE_URL = "postgresql+asyncpg://lexilingo:lexilingo_pass@localhost:5432/lexilingo_test"


@pytest.fixture
async def db_engine():
    """Create test database engine"""
    engine = create_async_engine(
        TEST_DATABASE_URL,
        poolclass=NullPool,
        echo=False
    )
    
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    
    yield engine
    
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    
    await engine.dispose()


@pytest.fixture
async def db_session(db_engine) -> AsyncGenerator[AsyncSession, None]:
    """Create test database session"""
    async_session = async_sessionmaker(
        db_engine,
        class_=AsyncSession,
        expire_on_commit=False
    )
    
    async with async_session() as session:
        yield session


@pytest.fixture
async def async_client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """Create async HTTP client for API testing"""
    from httpx import ASGITransport
    
    async def override_get_db():
        yield db_session
    
    app.dependency_overrides[get_db] = override_get_db
    
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        yield client
    
    app.dependency_overrides.clear()


@pytest.fixture
async def test_user(db_session: AsyncSession) -> User:
    """Create a test user"""
    # Use pre-hashed password to avoid bcrypt version detection issues in tests
    # This is the hash for password "testpass"
    user = User(
        email="test@example.com",
        username="testuser",
        hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
        display_name="Test User",
        is_active=True,
        is_verified=True,
        native_language="vi",
        target_language="en",
        level="beginner"
    )
    
    db_session.add(user)
    await db_session.commit()
    await db_session.refresh(user)
    
    return user


@pytest.fixture
def auth_headers(test_user: User) -> dict:
    """Create authentication headers with JWT token"""
    access_token = create_access_token(data={"sub": str(test_user.id)})
    return {"Authorization": f"Bearer {access_token}"}


@pytest.fixture
async def test_course(db_session: AsyncSession) -> Course:
    """Create a test course"""
    course = Course(
        title="Test Course",
        description="A test course for learning",
        language="en",  # Required field
        level="beginner",
        is_published=True,
        total_xp=1000,
        estimated_duration=30
    )
    
    db_session.add(course)
    await db_session.commit()
    await db_session.refresh(course)
    
    return course


@pytest.fixture
async def test_unit(db_session: AsyncSession, test_course: Course) -> Unit:
    """Create a test unit"""
    unit = Unit(
        course_id=test_course.id,
        title="Test Unit 1",
        description="First test unit",
        order_index=0,
        background_color="#2196F3"
    )
    
    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)
    
    return unit


@pytest.fixture
async def test_lesson(db_session: AsyncSession, test_unit: Unit, test_course: Course) -> Lesson:
    """Create a test lesson"""
    lesson = Lesson(
        course_id=test_course.id,
        unit_id=test_unit.id,
        title="Test Lesson 1",
        description="First test lesson",
        order_index=0,
        lesson_type="vocabulary",
        xp_reward=50,
        pass_threshold=70,
        content={"questions": []}
    )
    
    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)
    
    return lesson


@pytest.fixture
async def test_course_with_units(
    db_session: AsyncSession,
    test_course: Course
) -> Course:
    """Create a test course with multiple units and lessons"""
    
    # Create 3 units
    units = []
    for i in range(3):
        unit = Unit(
            course_id=test_course.id,
            title=f"Unit {i+1}",
            description=f"Unit {i+1} description",
            order_index=i,
            background_color="#2196F3"
        )
        db_session.add(unit)
        units.append(unit)
    
    await db_session.flush()
    
    # Create 2 lessons per unit
    for unit in units:
        for j in range(2):
            lesson = Lesson(
                course_id=test_course.id,
                unit_id=unit.id,
                title=f"{unit.title} - Lesson {j+1}",
                description=f"Lesson {j+1} in {unit.title}",
                order_index=j,
                lesson_type="vocabulary",
                xp_reward=50,
                pass_threshold=70,
                content={"questions": []}
            )
            db_session.add(lesson)
    
    await db_session.commit()
    await db_session.refresh(test_course)
    
    return test_course


@pytest.fixture
async def test_lesson_attempt(
    db_session: AsyncSession,
    test_user: User,
    test_lesson: Lesson
) -> LessonAttempt:
    """Create a test lesson attempt"""
    from datetime import datetime
    
    attempt = LessonAttempt(
        user_id=test_user.id,
        lesson_id=test_lesson.id,
        started_at=datetime.utcnow(),
        total_questions=10,
        lives_remaining=3,
        hints_used=0,
        passed=False,
        score=0,
        xp_earned=0,
        time_spent_ms=0,
        correct_answers=0
    )
    
    db_session.add(attempt)
    await db_session.commit()
    await db_session.refresh(attempt)
    
    return attempt


@pytest.fixture
async def test_vocabulary(db_session: AsyncSession) -> VocabularyItem:
    """Create test vocabulary"""
    vocab = VocabularyItem(
        word="hello",
        translation="xin chào",
        part_of_speech="interjection",
        pronunciation="həˈləʊ",
        example_sentence="Hello, how are you?",
        difficulty_level="beginner",
        topic="greetings",
        status="active"
    )
    
    db_session.add(vocab)
    await db_session.commit()
    await db_session.refresh(vocab)
    
    return vocab
