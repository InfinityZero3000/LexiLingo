"""
PostgreSQL Database Manager

Async SQLAlchemy setup following Repository pattern
"""

import logging
from typing import AsyncGenerator
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    AsyncEngine,
    create_async_engine,
    async_sessionmaker
)
from sqlalchemy.orm import declarative_base
from sqlalchemy.pool import NullPool

from app.core.config import settings

logger = logging.getLogger(__name__)

# Base class for SQLAlchemy models
Base = declarative_base()

# SQLite does not support connection pooling — use NullPool instead.
_is_sqlite = settings.DATABASE_URL.startswith("sqlite")
_db_url = settings.async_database_url  # normalises postgres:// → postgresql+asyncpg://

if _is_sqlite:
    engine: AsyncEngine = create_async_engine(
        _db_url,
        echo=settings.DB_ECHO,
        poolclass=NullPool,
        connect_args={"timeout": 30},  # wait up to 30s for a locked DB
    )
else:
    engine: AsyncEngine = create_async_engine(
        _db_url,
        echo=settings.DB_ECHO,
        pool_size=settings.effective_pool_size,
        max_overflow=settings.effective_max_overflow,
        pool_recycle=1800,          # recycle connections every 30 min to avoid stale handles
        pool_timeout=30,            # wait up to 30s for a free connection before raising
        pool_pre_ping=True,         # verify connection health before checkout
        pool_use_lifo=True,         # reuse recently-returned connections (better cache locality)
    )

# Session factory
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """
    Dependency for getting async database session.
    
    Usage in FastAPI routes:
        @router.get("/users")
        async def get_users(db: AsyncSession = Depends(get_db)):
            ...
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db():
    """
    Initialize database (create all tables).
    
    For production, use Alembic migrations instead.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        # Enable WAL mode for SQLite: allows concurrent reads during writes
        if _is_sqlite:
            await conn.execute(text("PRAGMA journal_mode=WAL"))
            await conn.execute(text("PRAGMA synchronous=NORMAL"))
    logger.info("Database tables created")


async def close_db():
    """Close database connections."""
    await engine.dispose()
    logger.info("Database connections closed")
