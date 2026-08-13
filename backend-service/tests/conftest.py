"""
Pytest Configuration and Fixtures
Shared test fixtures for backend API tests
"""

# ruff: noqa: E402

import os
import sys
from collections.abc import AsyncGenerator
from pathlib import Path

import asyncpg
import pytest
from httpx import AsyncClient
from sqlalchemy import select, text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.pool import NullPool

BACKEND_SERVICE_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_SERVICE_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_SERVICE_ROOT))

# Force DEBUG=False before app settings are imported so that production-only
# guards do not activate in tests and settings validation always uses safe defaults.
os.environ["DEBUG"] = "false"

# Keep tests isolated from local/prod env-switch state.
# Using APP_ENV=testing ensures production-only middleware (e.g., TrustedHost)
# does not break ASGI test client requests to http://test.
os.environ["APP_ENV"] = "testing"

from app.core.database import Base, get_db
from app.core.security import create_access_token
from app.main import app
from app.models.course import Course, Lesson, Unit
from app.models.progress import LessonAttempt
from app.models.rbac import Role
from app.models.user import User
from app.models.vocabulary import VocabularyItem


@pytest.fixture(autouse=True)
def disable_rate_limiting(monkeypatch):
    """
    Bypass rate limiting middleware for all tests.
    Patches the class-level _testing flag which is checked at dispatch time
    (not captured in self.dispatch_func), so monkeypatch works correctly.
    """
    from app.core.middleware import RateLimitMiddleware

    monkeypatch.setattr(RateLimitMiddleware, "_testing", True)


# Test database URL (use separate test database, configurable via environment)
TEST_DATABASE_URL = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://lexilingo:lexilingo_pass@localhost:5432/lexilingo_test",
)

# Safety guard: refuse to wipe a database whose name does not end with _test.
# This prevents an accidental misconfigured TEST_DATABASE_URL from destroying
# a production or development database.
_db_name = TEST_DATABASE_URL.rstrip("/").rsplit("/", 1)[-1]
if not _db_name.endswith("_test"):
    raise RuntimeError(
        f"TEST_DATABASE_URL database name '{_db_name}' does not end with '_test'. "
        "Refusing to drop/recreate schema to protect non-test databases. "
        "Set TEST_DATABASE_URL to a database whose name ends with '_test'."
    )


async def _reset_public_schema(engine) -> None:
    """Fully reset public schema to keep enum/table state deterministic between tests."""
    async with engine.begin() as conn:
        await conn.execute(text("DROP SCHEMA IF EXISTS public CASCADE"))
        await conn.execute(text("CREATE SCHEMA public"))
        await conn.run_sync(Base.metadata.create_all)


def _quote_pg_identifier(identifier: str) -> str:
    return f'"{identifier.replace(chr(34), chr(34) * 2)}"'


async def _ensure_test_database_exists() -> None:
    """Create the configured PostgreSQL test database if it is missing."""
    url = make_url(TEST_DATABASE_URL)
    if url.get_backend_name() != "postgresql":
        return

    db_name = url.database
    if not db_name:
        raise RuntimeError("TEST_DATABASE_URL must include a database name")
    if not db_name.endswith("_test"):
        raise RuntimeError(
            f"TEST_DATABASE_URL database name '{db_name}' does not end with '_test'."
        )

    maintenance_db = os.getenv("TEST_MAINTENANCE_DATABASE", "postgres")
    owner_clause = f" OWNER {_quote_pg_identifier(url.username)}" if url.username else ""
    connection_attempts = [
        {
            "user": url.username,
            "password": url.password,
            "database": maintenance_db,
            "host": url.host or "localhost",
            "port": url.port or 5432,
        },
        {
            "database": maintenance_db,
        },
    ]
    last_error: Exception | None = None

    for connection_kwargs in connection_attempts:
        filtered_kwargs = {
            key: value for key, value in connection_kwargs.items() if value is not None
        }
        try:
            conn = await asyncpg.connect(**filtered_kwargs)
        except Exception as exc:
            last_error = exc
            continue

        try:
            exists = await conn.fetchval(
                "SELECT 1 FROM pg_database WHERE datname = $1",
                db_name,
            )
            if not exists:
                await conn.execute(f"CREATE DATABASE {_quote_pg_identifier(db_name)}{owner_clause}")
            return
        except asyncpg.InsufficientPrivilegeError as exc:
            last_error = exc
        finally:
            await conn.close()

    raise RuntimeError(
        f"Unable to create PostgreSQL test database '{db_name}'. "
        "Create it manually or use a maintenance role with CREATEDB privileges."
    ) from last_error


@pytest.fixture
async def db_engine():
    """Create test database engine"""
    await _ensure_test_database_exists()

    engine = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool, echo=False)

    await _reset_public_schema(engine)

    yield engine

    await _reset_public_schema(engine)

    await engine.dispose()


@pytest.fixture
async def db_session(db_engine) -> AsyncGenerator[AsyncSession, None]:
    """Create test database session"""
    async_session = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)

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
        level="beginner",
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
async def admin_user(db_session: AsyncSession) -> User:
    """Create a test admin user with admin role for testing admin endpoints."""
    # Check if Admin role already exists to avoid unique constraint violations
    res = await db_session.execute(select(Role).where(Role.name == "Admin"))
    admin_role = res.scalar_one_or_none()

    if not admin_role:
        admin_role = Role(
            name="Admin",
            slug="admin",
            level=1,
            description="Admin role",
            is_system=True,
            is_active=True,
        )
        db_session.add(admin_role)
        await db_session.commit()
        await db_session.refresh(admin_role)

    # Check if admin user already exists to avoid unique constraint violations
    res_user = await db_session.execute(select(User).where(User.email == "admin@example.com"))
    user = res_user.scalar_one_or_none()

    if not user:
        user = User(
            email="admin@example.com",
            username="adminuser",
            hashed_password="$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS6NzE3Fu",
            display_name="Admin User",
            is_active=True,
            is_verified=True,
            native_language="vi",
            target_language="en",
            level="beginner",
            role_id=admin_role.id,
        )
        db_session.add(user)
        await db_session.commit()
        await db_session.refresh(user)
    return user


@pytest.fixture
def admin_headers(admin_user: User) -> dict:
    """Create authentication headers with JWT token for an admin user."""
    access_token = create_access_token(data={"sub": str(admin_user.id)})
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
        estimated_duration=30,
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
        background_color="#2196F3",
    )

    db_session.add(unit)
    await db_session.commit()
    await db_session.refresh(unit)

    return unit


@pytest.fixture
async def test_lesson(db_session: AsyncSession, test_unit: Unit, test_course: Course) -> Lesson:
    """Create a test lesson with exercises for testing answer submission"""
    lesson = Lesson(
        course_id=test_course.id,
        unit_id=test_unit.id,
        title="Test Lesson 1",
        description="First test lesson",
        order_index=0,
        lesson_type="vocabulary",
        xp_reward=50,
        pass_threshold=70,
        content={
            "exercises": [
                {
                    "id": "00000000-0000-0000-0000-000000000001",
                    "type": "multiple_choice",
                    "question": "What is the main topic?",
                    "options": ["Grammar fundamentals", "Advanced vocabulary", "Pronunciation"],
                    "correct_answer": "Grammar fundamentals",
                    "explanation": "This lesson covers grammar fundamentals.",
                },
                {
                    "id": "00000000-0000-0000-0000-000000000002",
                    "type": "fill_blank",
                    "question": "Complete: I ___ learning.",
                    "correct_answer": "am",
                    "explanation": "Use 'am' for first person singular.",
                },
            ]
        },
    )

    db_session.add(lesson)
    await db_session.commit()
    await db_session.refresh(lesson)

    return lesson


@pytest.fixture
async def test_course_with_units(db_session: AsyncSession, test_course: Course) -> Course:
    """Create a test course with multiple units and lessons"""

    # Create 3 units
    units = []
    for i in range(3):
        unit = Unit(
            course_id=test_course.id,
            title=f"Unit {i + 1}",
            description=f"Unit {i + 1} description",
            order_index=i,
            background_color="#2196F3",
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
                title=f"{unit.title} - Lesson {j + 1}",
                description=f"Lesson {j + 1} in {unit.title}",
                order_index=j,
                lesson_type="vocabulary",
                xp_reward=50,
                pass_threshold=70,
                content={
                    "exercises": [
                        {
                            "id": f"{unit.title}-{j + 1}-1",
                            "type": "multiple_choice",
                            "question": "Placeholder?",
                            "correct_answer": "yes",
                        }
                    ]
                },
            )
            db_session.add(lesson)

    await db_session.commit()
    await db_session.refresh(test_course)

    return test_course


@pytest.fixture
async def test_lesson_attempt(
    db_session: AsyncSession, test_user: User, test_lesson: Lesson
) -> LessonAttempt:
    """Create a test lesson attempt"""
    from datetime import UTC, datetime

    attempt = LessonAttempt(
        user_id=test_user.id,
        lesson_id=test_lesson.id,
        started_at=datetime.now(UTC),
        total_questions=10,
        lives_remaining=3,
        hints_used=0,
        passed=False,
        score=0,
        xp_earned=0,
        time_spent_ms=0,
        correct_answers=0,
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
        definition="A greeting or expression of goodwill",
        translation={"vi": "xin chào", "examples": ["Hello, how are you?"]},
        part_of_speech="interjection",
        pronunciation="həˈləʊ",
        difficulty_level="A1",
    )

    db_session.add(vocab)
    await db_session.commit()
    await db_session.refresh(vocab)

    return vocab
