---
name: migration-alembic-workflow
description: Alembic migration workflow for backend-service. Always use autogenerate, review the diff, add data migrations when needed, never edit production migration files.
impact: HIGH
---

# Alembic Migration Workflow

## Context

The `backend-service` uses Alembic (via `alembic.ini`) for PostgreSQL schema migrations. Every new ORM model or column change needs a migration. Never run raw DDL or `CREATE TABLE` manually.

## Workflow

```bash
# 1. Make sure the venv is active
cd backend-service
source venv/bin/activate

# 2. Update your SQLAlchemy model (e.g., app/models/notification.py)

# 3. Generate the migration (autogenerate compares models to current DB state)
alembic revision --autogenerate -m "add_notifications_table"

# 4. Review the generated file in alembic/versions/
# Verify upgrade() and downgrade() are correct

# 5. Apply it
alembic upgrade head

# 6. To roll back (development only!)
alembic downgrade -1
```

## New Model Pattern (SQLAlchemy 2.0 mapped_column)

```python
# app/models/notification.py
"""
Notification Model

Stores user notifications from Firebase FCM and backend events.
"""

from datetime import datetime
from typing import Optional
from sqlalchemy import String, Boolean, Text, ForeignKey, Index
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class Notification(Base):
    __tablename__ = "notifications"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    type: Mapped[str] = mapped_column(String(50), nullable=False)  # streak, review, achievement, system
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    data: Mapped[Optional[str]] = mapped_column(Text, nullable=True)  # JSON string
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, nullable=False)
    read_at: Mapped[Optional[datetime]] = mapped_column(nullable=True)

    # Relationship back to user
    user = relationship("User", back_populates="notifications")

    # Index for fast user query
    __table_args__ = (
        Index("ix_notifications_user_id_created_at", "user_id", "created_at"),
    )
```

## Course Category Model (if categories not in DB yet)

```python
# app/models/course_category.py
from sqlalchemy import String, Text, Integer
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.database import Base


class CourseCategory(Base):
    __tablename__ = "course_categories"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False, unique=True)
    description: Mapped[str] = mapped_column(Text, nullable=True)
    icon: Mapped[str] = mapped_column(String(50), nullable=True)   # emoji or icon name
    sort_order: Mapped[int] = mapped_column(Integer, default=0)

    courses = relationship("Course", back_populates="category")
```

## Generated Migration Review Checklist

After `alembic revision --autogenerate`, open the file and verify:

- [ ] `upgrade()` contains `op.create_table(...)` or `op.add_column(...)` as expected
- [ ] `downgrade()` reverses it correctly with `op.drop_table(...)` / `op.drop_column(...)`
- [ ] Foreign keys reference the correct table and cascade rule
- [ ] Indexes are present for fields used in WHERE clauses
- [ ] No unexpected drops or modifications to existing tables

## Incorrect Pattern

```python
# Anti-pattern: raw DDL outside Alembic
async def create_tables(engine):
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)  # ❌ bypasses Alembic history

# Anti-pattern: editing an already-applied migration file
# Never modify alembic/versions/*.py files that have been applied to production
```
