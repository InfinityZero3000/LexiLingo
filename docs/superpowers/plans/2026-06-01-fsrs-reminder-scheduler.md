# FSRS Reminder Scheduler Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a backend-managed FSRS reminder system that sends real in-app notifications, FCM push notifications, and occasional review reminder emails without breaking the existing vocabulary review or settings flows.

**Architecture:** Keep the existing FSRS scheduling source of truth: `user_vocabulary.next_review_date`. Add reminder preferences and delivery audit tables, then run Celery worker plus Celery beat as separate processes. The FastAPI app remains request/response only; worker processes scan due preferences, count FSRS due vocabulary, dedupe deliveries, create `notifications` rows, send FCM, and send email only on the configured cadence.

**Tech Stack:** FastAPI, SQLAlchemy async, Alembic, PostgreSQL, Redis, Celery, Firebase Admin SDK, SMTP email templates, Flutter Provider, FCM, local notification fallback, sqflite/shared_preferences.

---

## Safety Strategy

- Default all new backend reminder sending behind `REMINDERS_ENABLED=false`.
- Create new tables instead of changing existing reminder behavior in place.
- Keep existing Flutter `notificationEnabled` and `notificationTime` fields backward compatible.
- Keep local daily notification as fallback only when backend sync or FCM is unavailable.
- Make worker idempotent with a unique delivery `dedupe_key`.
- Do not change the existing FSRS formula and review submission behavior in the same deployment. First add tests and an adapter boundary, then let reminder services read the already-computed `next_review_date`.
- Deploy in this order: migrations, API fields disabled, Flutter settings sync, worker dry-run, worker live.

## File Structure

### Backend files to create

- `backend-service/app/models/reminder.py`
  - SQLAlchemy models for user reminder preferences and reminder delivery audit.
- `backend-service/app/schemas/reminders.py`
  - Pydantic request/response schemas for user-configurable reminder settings.
- `backend-service/app/routes/reminders.py`
  - Authenticated preference endpoints.
- `backend-service/app/schemas/notifications.py`
  - Pydantic schemas for persisted notifications.
- `backend-service/app/routes/notifications.py`
  - Authenticated notification list/read endpoints.
- `backend-service/app/services/fsrs_scheduler_service.py`
  - Thin adapter around due-count and due-date checks. Keeps scheduler independent from review submission internals.
- `backend-service/app/services/reminder_service.py`
  - Business logic for preference evaluation, due count checks, dedupe, DB notification creation, and channel dispatch.
- `backend-service/app/services/push_notification_service.py`
  - Firebase Admin FCM sender with graceful no-op when Firebase is not configured.
- `backend-service/app/core/celery_app.py`
  - Celery app configuration using Redis broker/backend.
- `backend-service/app/tasks/reminders.py`
  - Celery task entrypoint for scanning reminder preferences.
- `backend-service/app/templates/vocabulary_review_reminder.html`
  - HTML email template.
- `backend-service/app/templates/vocabulary_review_reminder.txt`
  - Plain text email template.
- `backend-service/alembic/versions/add_fsrs_reminder_scheduler.py`
  - Migration for new tables and indexes.
- `backend-service/tests/test_reminder_preferences_routes.py`
  - API tests for preference read/update.
- `backend-service/tests/test_notifications_routes.py`
  - API tests for notification list and read status.
- `backend-service/tests/test_fsrs_scheduler_service.py`
  - Deterministic due-count and next-check tests.
- `backend-service/tests/test_reminder_service.py`
  - Channel/cadence/dedupe tests.
- `backend-service/tests/test_push_notification_service.py`
  - Firebase sender tests with mocks.
- `backend-service/tests/test_email_service_review_reminder.py`
  - Template rendering and SMTP no-op tests.

### Backend files to modify

- `backend-service/requirements.txt`
  - Add Celery.
- `backend-service/.env.example`
  - Add reminder, Celery, and public app URL variables.
- `backend-service/app/core/config.py`
  - Add typed settings for reminders, Celery, and review deep links.
- `backend-service/app/models/__init__.py`
  - Import new reminder models for Alembic/create_all.
- `backend-service/app/main.py`
  - Include reminders and notifications routers.
- `backend-service/app/routes/devices.py`
  - Fix missing `select` and `and_` imports; keep route contract unchanged.
- `backend-service/app/services/email_service.py`
  - Add review reminder email method using existing SMTP helper.
- `backend-service/render.yaml`
  - Add worker and beat process definitions, disabled by env until configured.
- `docker-compose.yml`
  - Add backend Celery worker and beat services for local full-stack testing.
- `docker-compose.production.yml`
  - Add production worker and beat services.

### Flutter files to create

- `flutter-app/lib/features/user/data/datasources/settings_remote_data_source.dart`
  - Remote API bridge for reminder preferences.
- `flutter-app/lib/core/services/app_navigation_service.dart`
  - Global navigator key and notification route handling.
- `flutter-app/test/features/user/settings_model_test.dart`
  - Model parse/serialize tests for new reminder fields.
- `flutter-app/test/features/user/settings_provider_reminder_test.dart`
  - Provider behavior tests for backend sync and local fallback.

### Flutter files to modify

- `flutter-app/lib/features/user/domain/entities/settings.dart`
  - Add reminder channel and email cadence fields with safe defaults.
- `flutter-app/lib/features/user/data/models/settings_model.dart`
  - Parse both old local camelCase keys and new backend snake_case keys.
- `flutter-app/lib/features/user/data/repositories/settings_repository_impl.dart`
  - Read/write local settings and sync reminder preferences to backend.
- `flutter-app/lib/features/user/domain/repositories/settings_repository.dart`
  - Add reminder update method if needed.
- `flutter-app/lib/features/user/data/datasources/settings_local_data_source.dart`
  - Store new fields in sqflite.
- `flutter-app/lib/features/user/data/datasources/settings_local_data_source_web.dart`
  - Store new fields in shared_preferences.
- `flutter-app/lib/core/services/database_helper.dart`
  - Bump DB version and add nullable/defaulted settings columns.
- `flutter-app/lib/features/user/di/user_di.dart`
  - Inject `ApiClient` into settings repository.
- `flutter-app/lib/features/user/presentation/providers/settings_provider.dart`
  - Add update methods for push/email/cadence/min due count and backend sync.
- `flutter-app/lib/features/user/presentation/pages/settings_page.dart`
  - Extend notification card with review reminder controls.
- `flutter-app/lib/core/services/firebase_messaging_service.dart`
  - Fix device registration path from `/api/devices` to `/devices`; handle `vocabulary_review_reminder`.
- `flutter-app/lib/features/notifications/domain/entities/notification_entity.dart`
  - Add `vocabularyReviewReminder` type.
- `flutter-app/lib/features/notifications/presentation/pages/notifications_page.dart`
  - Navigate to review screen when tapping reminder notification.
- `flutter-app/lib/features/vocabulary/presentation/widgets/daily_review_card.dart`
  - Extract reusable navigation helper or add named route support.
- `flutter-app/lib/main.dart`
  - Add `navigatorKey` and `/vocabulary/review` named route.
- `flutter-app/assets/i18n/en.json`
- `flutter-app/assets/i18n/vi.json`
- `flutter-app/assets/i18n/ja.json`
- `flutter-app/assets/i18n/ko.json`
- `flutter-app/assets/i18n/zh.json`
- `flutter-app/assets/i18n/fr.json`
- `flutter-app/assets/i18n/es.json`
  - Add labels for push/email reminders and review notification copy.
- `flutter-app/test/core/services/firebase_messaging_service_test.dart`
  - Update expected device registration path and reminder payload routing.
- `flutter-app/test/features/notifications/notification_entity_test.dart`
  - Add type parsing coverage.

---

## Chunk 1: Backend Data Model And Config

### Task 1: Add reminder tables

**Files:**
- Create: `backend-service/app/models/reminder.py`
- Modify: `backend-service/app/models/__init__.py`
- Create: `backend-service/alembic/versions/add_fsrs_reminder_scheduler.py`
- Test: `backend-service/tests/test_reminder_preferences_routes.py`

- [ ] **Step 1: Write failing model import test**

Add a small assertion inside `backend-service/tests/test_reminder_preferences_routes.py`:

```python
from app.models.reminder import ReminderDelivery, UserReminderPreference


def test_reminder_models_have_expected_tables():
    assert UserReminderPreference.__tablename__ == "user_reminder_preferences"
    assert ReminderDelivery.__tablename__ == "reminder_deliveries"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_preferences_routes.py::test_reminder_models_have_expected_tables -q
```

Expected: FAIL with `ModuleNotFoundError: No module named 'app.models.reminder'`.

- [ ] **Step 3: Create `backend-service/app/models/reminder.py`**

Implement:

```python
import uuid
from datetime import datetime, timezone
from sqlalchemy import Boolean, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.core.db_types import GUID, TZDateTime, PortableJSON


class UserReminderPreference(Base):
    __tablename__ = "user_reminder_preferences"

    user_id: Mapped[uuid.UUID] = mapped_column(
        GUID(),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    push_enabled: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    email_enabled: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    reminder_time_local: Mapped[str] = mapped_column(String(5), default="09:00", nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), default="Asia/Ho_Chi_Minh", nullable=False)
    min_due_count: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    email_cadence_days: Mapped[int] = mapped_column(Integer, default=7, nullable=False)
    next_check_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc), nullable=False, index=True)
    last_push_sent_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    last_email_sent_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc), onupdate=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (
        Index("ix_user_reminder_preferences_enabled_next", "enabled", "next_check_at"),
    )


class ReminderDelivery(Base):
    __tablename__ = "reminder_deliveries"

    id: Mapped[uuid.UUID] = mapped_column(GUID(), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(GUID(), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    channel: Mapped[str] = mapped_column(String(20), nullable=False)
    reminder_type: Mapped[str] = mapped_column(String(50), default="vocabulary_review", nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="queued", nullable=False)
    due_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    dedupe_key: Mapped[str] = mapped_column(String(180), nullable=False)
    scheduled_for: Mapped[datetime] = mapped_column(TZDateTime, nullable=False, index=True)
    sent_at: Mapped[datetime | None] = mapped_column(TZDateTime, nullable=True)
    error: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    data: Mapped[dict | None] = mapped_column(PortableJSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(TZDateTime, default=lambda: datetime.now(timezone.utc), nullable=False)

    __table_args__ = (
        UniqueConstraint("dedupe_key", name="uq_reminder_deliveries_dedupe_key"),
        Index("ix_reminder_delivery_user_channel_created", "user_id", "channel", "created_at"),
    )
```

- [ ] **Step 4: Import models in `backend-service/app/models/__init__.py`**

Add:

```python
from app.models.reminder import UserReminderPreference, ReminderDelivery
```

Add names to `__all__`.

- [ ] **Step 5: Create Alembic migration**

Create `backend-service/alembic/versions/add_fsrs_reminder_scheduler.py` with only additive DDL:

```python
"""add fsrs reminder scheduler

Revision ID: add_fsrs_reminder_scheduler
Revises: 49b1f1d9b26c
Create Date: 2026-06-01
"""

from alembic import op
import sqlalchemy as sa
from app.core.db_types import GUID, TZDateTime, PortableJSON

revision = "add_fsrs_reminder_scheduler"
down_revision = "fix_badge_cdn_urls"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "user_reminder_preferences",
        sa.Column("user_id", GUID(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("push_enabled", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("email_enabled", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("reminder_time_local", sa.String(length=5), nullable=False, server_default="09:00"),
        sa.Column("timezone", sa.String(length=64), nullable=False, server_default="Asia/Ho_Chi_Minh"),
        sa.Column("min_due_count", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("email_cadence_days", sa.Integer(), nullable=False, server_default="7"),
        sa.Column("next_check_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("last_push_sent_at", TZDateTime(), nullable=True),
        sa.Column("last_email_sent_at", TZDateTime(), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_user_reminder_preferences_enabled_next", "user_reminder_preferences", ["enabled", "next_check_at"])
    op.create_index("ix_user_reminder_preferences_next_check_at", "user_reminder_preferences", ["next_check_at"])

    op.create_table(
        "reminder_deliveries",
        sa.Column("id", GUID(), primary_key=True),
        sa.Column("user_id", GUID(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("channel", sa.String(length=20), nullable=False),
        sa.Column("reminder_type", sa.String(length=50), nullable=False, server_default="vocabulary_review"),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="queued"),
        sa.Column("due_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("dedupe_key", sa.String(length=180), nullable=False),
        sa.Column("scheduled_for", TZDateTime(), nullable=False),
        sa.Column("sent_at", TZDateTime(), nullable=True),
        sa.Column("error", sa.String(length=1000), nullable=True),
        sa.Column("data", PortableJSON(), nullable=True),
        sa.Column("created_at", TZDateTime(), nullable=False, server_default=sa.func.now()),
        sa.UniqueConstraint("dedupe_key", name="uq_reminder_deliveries_dedupe_key"),
    )
    op.create_index("ix_reminder_deliveries_user_id", "reminder_deliveries", ["user_id"])
    op.create_index("ix_reminder_deliveries_scheduled_for", "reminder_deliveries", ["scheduled_for"])
    op.create_index("ix_reminder_delivery_user_channel_created", "reminder_deliveries", ["user_id", "channel", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_reminder_delivery_user_channel_created", table_name="reminder_deliveries")
    op.drop_index("ix_reminder_deliveries_scheduled_for", table_name="reminder_deliveries")
    op.drop_index("ix_reminder_deliveries_user_id", table_name="reminder_deliveries")
    op.drop_table("reminder_deliveries")
    op.drop_index("ix_user_reminder_preferences_next_check_at", table_name="user_reminder_preferences")
    op.drop_index("ix_user_reminder_preferences_enabled_next", table_name="user_reminder_preferences")
    op.drop_table("user_reminder_preferences")
```

Confirm `down_revision` against the actual current head before applying. At plan time, the latest observed head is `fix_badge_cdn_urls`.

- [ ] **Step 6: Run model test**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_preferences_routes.py::test_reminder_models_have_expected_tables -q
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend-service/app/models/reminder.py backend-service/app/models/__init__.py backend-service/alembic/versions/add_fsrs_reminder_scheduler.py backend-service/tests/test_reminder_preferences_routes.py
git commit -m "feat: add reminder scheduler data model"
```

### Task 2: Add backend config and dependencies

**Files:**
- Modify: `backend-service/requirements.txt`
- Modify: `backend-service/app/core/config.py`
- Modify: `backend-service/.env.example`

- [ ] **Step 1: Add failing config test**

Add to `backend-service/tests/test_reminder_service.py`:

```python
def test_reminder_settings_have_safe_defaults():
    from app.core.config import settings

    assert settings.REMINDERS_ENABLED is False
    assert settings.REMINDER_DEFAULT_TIMEZONE == "Asia/Ho_Chi_Minh"
    assert settings.REMINDER_SCAN_BATCH_SIZE >= 1
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_service.py::test_reminder_settings_have_safe_defaults -q
```

Expected: FAIL because config fields do not exist.

- [ ] **Step 3: Add Celery dependency**

In `backend-service/requirements.txt` add:

```txt
# Background jobs
celery[redis]>=5.4,<6
```

- [ ] **Step 4: Add settings in `backend-service/app/core/config.py`**

Add near Redis/Firebase settings:

```python
    # Reminder scheduler
    REMINDERS_ENABLED: bool = False
    REMINDER_DRY_RUN: bool = True
    REMINDER_SCAN_BATCH_SIZE: int = 250
    REMINDER_SCAN_INTERVAL_SECONDS: int = 300
    REMINDER_DEFAULT_TIMEZONE: str = "Asia/Ho_Chi_Minh"
    REMINDER_REVIEW_ROUTE: str = "/vocabulary/review"
    APP_PUBLIC_URL: str = "https://lexilingo.me"

    # Celery
    CELERY_BROKER_URL: str | None = None
    CELERY_RESULT_BACKEND: str | None = None

    @property
    def effective_celery_broker_url(self) -> str:
        return self.CELERY_BROKER_URL or self.REDIS_URL

    @property
    def effective_celery_result_backend(self) -> str:
        return self.CELERY_RESULT_BACKEND or self.REDIS_URL
```

- [ ] **Step 5: Document env vars in `.env.example`**

Add:

```env
# Reminder scheduler
REMINDERS_ENABLED=false
REMINDER_DRY_RUN=true
REMINDER_SCAN_BATCH_SIZE=250
REMINDER_SCAN_INTERVAL_SECONDS=300
REMINDER_DEFAULT_TIMEZONE=Asia/Ho_Chi_Minh
REMINDER_REVIEW_ROUTE=/vocabulary/review
APP_PUBLIC_URL=https://lexilingo.me

# Celery. Defaults to REDIS_URL when empty.
CELERY_BROKER_URL=
CELERY_RESULT_BACKEND=
```

- [ ] **Step 6: Run config test**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_service.py::test_reminder_settings_have_safe_defaults -q
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend-service/requirements.txt backend-service/app/core/config.py backend-service/.env.example backend-service/tests/test_reminder_service.py
git commit -m "feat: configure reminder scheduler defaults"
```

---

## Chunk 2: Backend Preference And Notification APIs

### Task 3: Add reminder preference endpoints

**Files:**
- Create: `backend-service/app/schemas/reminders.py`
- Create: `backend-service/app/routes/reminders.py`
- Modify: `backend-service/app/main.py`
- Test: `backend-service/tests/test_reminder_preferences_routes.py`

- [ ] **Step 1: Write route tests first**

Test cases:

```python
@pytest.mark.asyncio
async def test_get_reminder_preferences_creates_default(async_client, auth_headers):
    response = await async_client.get("/api/v1/users/me/reminder-preferences", headers=auth_headers)
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["enabled"] is False
    assert data["push_enabled"] is True
    assert data["email_enabled"] is False
    assert data["reminder_time_local"] == "09:00"


@pytest.mark.asyncio
async def test_update_reminder_preferences(async_client, auth_headers):
    payload = {
        "enabled": True,
        "push_enabled": True,
        "email_enabled": True,
        "reminder_time_local": "20:30",
        "timezone": "Asia/Ho_Chi_Minh",
        "min_due_count": 3,
        "email_cadence_days": 7,
    }
    response = await async_client.put(
        "/api/v1/users/me/reminder-preferences",
        headers=auth_headers,
        json=payload,
    )
    assert response.status_code == 200
    assert response.json()["data"]["reminder_time_local"] == "20:30"
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_preferences_routes.py -q
```

Expected: FAIL with 404 for new route.

- [ ] **Step 3: Create schemas**

In `backend-service/app/schemas/reminders.py`:

```python
from datetime import datetime
from pydantic import BaseModel, Field, field_validator


class ReminderPreferenceResponse(BaseModel):
    enabled: bool
    push_enabled: bool
    email_enabled: bool
    reminder_time_local: str
    timezone: str
    min_due_count: int
    email_cadence_days: int
    next_check_at: datetime
    last_push_sent_at: datetime | None = None
    last_email_sent_at: datetime | None = None

    class Config:
        from_attributes = True


class ReminderPreferenceUpdate(BaseModel):
    enabled: bool | None = None
    push_enabled: bool | None = None
    email_enabled: bool | None = None
    reminder_time_local: str | None = Field(default=None, pattern=r"^\d{2}:\d{2}$")
    timezone: str | None = Field(default=None, min_length=1, max_length=64)
    min_due_count: int | None = Field(default=None, ge=1, le=1000)
    email_cadence_days: int | None = Field(default=None, ge=1, le=30)

    @field_validator("reminder_time_local")
    @classmethod
    def validate_time(cls, value: str | None) -> str | None:
        if value is None:
            return value
        hour, minute = [int(part) for part in value.split(":")]
        if hour > 23 or minute > 59:
            raise ValueError("reminder_time_local must be HH:MM")
        return value
```

- [ ] **Step 4: Create route**

In `backend-service/app/routes/reminders.py`, implement:

```python
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.reminder import UserReminderPreference
from app.models.user import User
from app.schemas.common import ApiResponse
from app.schemas.reminders import ReminderPreferenceResponse, ReminderPreferenceUpdate

router = APIRouter(prefix="/users/me/reminder-preferences", tags=["Reminder Preferences"])


def compute_next_check_at(time_text: str, timezone_name: str, now_utc: datetime | None = None) -> datetime:
    now_utc = now_utc or datetime.now(timezone.utc)
    try:
        tz = ZoneInfo(timezone_name)
    except ZoneInfoNotFoundError:
        tz = ZoneInfo(settings.REMINDER_DEFAULT_TIMEZONE)
    hour, minute = [int(part) for part in time_text.split(":")]
    local_now = now_utc.astimezone(tz)
    candidate = local_now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if candidate <= local_now:
        candidate = candidate + timedelta(days=1)
    return candidate.astimezone(timezone.utc)
```

Then add GET and PUT endpoints that create a default row when missing and recalculate `next_check_at` on update.

- [ ] **Step 5: Include router in `backend-service/app/main.py`**

Add import:

```python
from app.routes.reminders import router as reminders_router
```

Add include:

```python
app.include_router(reminders_router, prefix=f"{settings.API_V1_PREFIX}", tags=["Reminder Preferences"])
```

- [ ] **Step 6: Run route tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_preferences_routes.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend-service/app/schemas/reminders.py backend-service/app/routes/reminders.py backend-service/app/main.py backend-service/tests/test_reminder_preferences_routes.py
git commit -m "feat: add reminder preference endpoints"
```

### Task 4: Add persisted notification endpoints

**Files:**
- Create: `backend-service/app/schemas/notifications.py`
- Create: `backend-service/app/routes/notifications.py`
- Modify: `backend-service/app/main.py`
- Test: `backend-service/tests/test_notifications_routes.py`

- [ ] **Step 1: Write tests**

Cover:

- unauthenticated requests return 401
- `GET /api/v1/notifications` returns only current user notifications
- `PATCH /api/v1/notifications/{notification_id}/read` marks one notification read
- `PATCH /api/v1/notifications/read-all` marks all current user notifications read

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_notifications_routes.py -q
```

Expected: FAIL with 404.

- [ ] **Step 3: Implement schemas**

Use:

```python
from datetime import datetime
from uuid import UUID
from pydantic import BaseModel


class NotificationResponse(BaseModel):
    id: UUID
    title: str
    body: str
    type: str
    data: dict | None = None
    is_read: bool
    read_at: datetime | None = None
    created_at: datetime

    class Config:
        from_attributes = True
```

- [ ] **Step 4: Implement routes**

Use existing `Notification` model. Return `app.schemas.common.ApiResponse` for list and single-object responses.

- [ ] **Step 5: Include router in `backend-service/app/main.py`**

Add:

```python
from app.routes.notifications import router as notifications_router
app.include_router(notifications_router, prefix=f"{settings.API_V1_PREFIX}/notifications", tags=["Notifications"])
```

- [ ] **Step 6: Run tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_notifications_routes.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend-service/app/schemas/notifications.py backend-service/app/routes/notifications.py backend-service/app/main.py backend-service/tests/test_notifications_routes.py
git commit -m "feat: expose persisted notifications"
```

---

## Chunk 3: FSRS Reminder Service

### Task 5: Add FSRS scheduler adapter

**Files:**
- Create: `backend-service/app/services/fsrs_scheduler_service.py`
- Test: `backend-service/tests/test_fsrs_scheduler_service.py`

- [ ] **Step 1: Write deterministic tests**

Cover:

- due count uses `UserVocabulary.next_review_date <= now`
- archived vocabulary is ignored
- no due vocabulary returns zero
- service accepts injected `now` so tests are stable

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_fsrs_scheduler_service.py -q
```

Expected: FAIL because service does not exist.

- [ ] **Step 3: Implement service**

Create a small adapter, not a new algorithm:

```python
from datetime import datetime, timezone
from uuid import UUID
from sqlalchemy import and_, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.vocabulary import UserVocabulary, VocabularyStatus


class FSRSSchedulerService:
    async def count_due_vocabulary(
        self,
        db: AsyncSession,
        *,
        user_id: UUID,
        now: datetime | None = None,
    ) -> int:
        now = now or datetime.now(timezone.utc)
        result = await db.execute(
            select(func.count()).select_from(UserVocabulary).where(
                and_(
                    UserVocabulary.user_id == user_id,
                    UserVocabulary.next_review_date <= now,
                    UserVocabulary.status != VocabularyStatus.ARCHIVED,
                )
            )
        )
        return int(result.scalar() or 0)
```

- [ ] **Step 4: Run tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_fsrs_scheduler_service.py -q
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add backend-service/app/services/fsrs_scheduler_service.py backend-service/tests/test_fsrs_scheduler_service.py
git commit -m "test: guard fsrs due scheduling contract"
```

### Task 6: Add push notification service

**Files:**
- Create: `backend-service/app/services/push_notification_service.py`
- Modify: `backend-service/app/routes/devices.py`
- Test: `backend-service/tests/test_push_notification_service.py`
- Test: `backend-service/tests/test_devices_routes.py`

- [ ] **Step 1: Write tests**

Cover:

- service returns `False` when Firebase credentials are absent
- service calls `firebase_admin.messaging.send_each_for_multicast` or equivalent when tokens exist
- invalid tokens do not crash reminder job
- `app/routes/devices.py` imports `select` and `and_`

- [ ] **Step 2: Run tests to verify current gaps**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_push_notification_service.py tests/test_devices_routes.py -q
```

Expected: FAIL for missing push service or device route import bugs.

- [ ] **Step 3: Fix device route imports**

In `backend-service/app/routes/devices.py`, add:

```python
from sqlalchemy import and_, select
```

- [ ] **Step 4: Implement `PushNotificationService`**

Use `app.core.firebase_auth._init_firebase_app()` so Firebase is initialized consistently. Send payload:

```python
{
    "type": "vocabulary_review_reminder",
    "route": settings.REMINDER_REVIEW_ROUTE,
    "due_count": str(due_count),
}
```

The method should be:

```python
async def send_review_reminder(
    self,
    *,
    tokens: list[str],
    due_count: int,
    title: str,
    body: str,
    data: dict[str, str],
) -> bool:
    ...
```

Return `False` when tokens are empty or Firebase is not configured. Log exceptions; do not raise to Celery unless the code bug is unrecoverable.

- [ ] **Step 5: Run tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_push_notification_service.py tests/test_devices_routes.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend-service/app/services/push_notification_service.py backend-service/app/routes/devices.py backend-service/tests/test_push_notification_service.py backend-service/tests/test_devices_routes.py
git commit -m "feat: add fcm review reminder sender"
```

### Task 7: Add review reminder email method and templates

**Files:**
- Modify: `backend-service/app/services/email_service.py`
- Create: `backend-service/app/templates/vocabulary_review_reminder.html`
- Create: `backend-service/app/templates/vocabulary_review_reminder.txt`
- Test: `backend-service/tests/test_email_service_review_reminder.py`

- [ ] **Step 1: Write tests**

Cover:

- template renders display name, due count, and review link
- missing SMTP returns `False` and logs no-send like existing reset/verification methods
- configured SMTP builds `EmailMessage` with subject `LexiLingo - Time to review your vocabulary`

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_email_service_review_reminder.py -q
```

Expected: FAIL because method/templates do not exist.

- [ ] **Step 3: Add templates**

Text template must include:

```txt
Hi {display_name},

You have {due_count} vocabulary review(s) waiting in LexiLingo.

Review now: {review_link}

You can change reminder settings here: {settings_link}
```

HTML template should match the existing email style but remain simple.

- [ ] **Step 4: Add email method**

In `EmailService` add:

```python
@classmethod
async def send_vocabulary_review_reminder_email(
    cls,
    *,
    to_email: str,
    display_name: str | None,
    due_count: int,
) -> bool:
    review_link = f"{settings.APP_PUBLIC_URL.rstrip('/')}{settings.REMINDER_REVIEW_ROUTE}"
    settings_link = f"{settings.APP_PUBLIC_URL.rstrip('/')}/settings"
    ...
```

Use `_render_template` and `_send_message_blocking` exactly like existing methods.

- [ ] **Step 5: Run tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_email_service_review_reminder.py -q
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add backend-service/app/services/email_service.py backend-service/app/templates/vocabulary_review_reminder.html backend-service/app/templates/vocabulary_review_reminder.txt backend-service/tests/test_email_service_review_reminder.py
git commit -m "feat: add vocabulary review reminder email"
```

### Task 8: Add reminder orchestration service

**Files:**
- Create: `backend-service/app/services/reminder_service.py`
- Test: `backend-service/tests/test_reminder_service.py`

- [ ] **Step 1: Write service tests**

Cover:

- disabled global `REMINDERS_ENABLED` returns zero sent
- `REMINDER_DRY_RUN=true` creates skipped/dry-run delivery records but does not call FCM/SMTP
- user preference disabled is skipped
- due count below `min_due_count` is skipped
- push delivery creates `Notification` and `ReminderDelivery`
- email respects `email_cadence_days`
- duplicate scan for same local date/channel does not send twice
- `next_check_at` is moved to next local reminder time after evaluation

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_service.py -q
```

Expected: FAIL because service does not exist.

- [ ] **Step 3: Implement helper methods**

In `ReminderService`, implement:

- `build_dedupe_key(user_id, channel, local_date)`
- `compute_next_check_at(reminder_time_local, timezone_name, now_utc)`
- `scan_due_preferences(db, now_utc, limit)`
- `process_preference(db, preference, now_utc)`

- [ ] **Step 4: Implement DB notification creation**

Notification rows should use:

```python
Notification(
    user_id=user.id,
    title="Vocabulary review is ready",
    body=f"You have {due_count} word{'s' if due_count != 1 else ''} to review.",
    type="vocabulary_review_reminder",
    data={
        "route": settings.REMINDER_REVIEW_ROUTE,
        "due_count": due_count,
    },
)
```

- [ ] **Step 5: Implement channel dispatch**

Push:

- load active tokens from `UserDevice` where `user_id == preference.user_id` and `fcm_token is not null`
- create delivery with `channel="push"`
- call `PushNotificationService.send_review_reminder`
- mark delivery `sent`, `skipped`, or `failed`

Email:

- only if `email_enabled`
- only if user has email
- only if `last_email_sent_at` is null or older than `email_cadence_days`
- create delivery with `channel="email"`
- call `EmailService.send_vocabulary_review_reminder_email`

- [ ] **Step 6: Run tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_service.py -q
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add backend-service/app/services/reminder_service.py backend-service/tests/test_reminder_service.py
git commit -m "feat: orchestrate fsrs reminders"
```

---

## Chunk 4: Celery Worker And Deployment

### Task 9: Add Celery app and reminder task

**Files:**
- Create: `backend-service/app/core/celery_app.py`
- Create: `backend-service/app/tasks/reminders.py`
- Test: `backend-service/tests/test_reminder_service.py`

- [ ] **Step 1: Write Celery config test**

Add:

```python
def test_celery_has_reminder_schedule():
    from app.core.celery_app import celery_app

    assert "scan-fsrs-reminders" in celery_app.conf.beat_schedule
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_service.py::test_celery_has_reminder_schedule -q
```

Expected: FAIL because Celery app does not exist.

- [ ] **Step 3: Implement Celery app**

`backend-service/app/core/celery_app.py`:

```python
from celery import Celery
from app.core.config import settings

celery_app = Celery(
    "lexilingo",
    broker=settings.effective_celery_broker_url,
    backend=settings.effective_celery_result_backend,
    include=["app.tasks.reminders"],
)

celery_app.conf.timezone = "UTC"
celery_app.conf.enable_utc = True
celery_app.conf.task_acks_late = True
celery_app.conf.worker_prefetch_multiplier = 1
celery_app.conf.beat_schedule = {
    "scan-fsrs-reminders": {
        "task": "app.tasks.reminders.scan_fsrs_reminders",
        "schedule": settings.REMINDER_SCAN_INTERVAL_SECONDS,
    }
}
```

- [ ] **Step 4: Implement task**

`backend-service/app/tasks/reminders.py`:

```python
import asyncio
import logging
from datetime import datetime, timezone

from app.core.celery_app import celery_app
from app.core.database import AsyncSessionLocal
from app.services.reminder_service import ReminderService

logger = logging.getLogger(__name__)


@celery_app.task(name="app.tasks.reminders.scan_fsrs_reminders")
def scan_fsrs_reminders() -> dict:
    return asyncio.run(_scan())


async def _scan() -> dict:
    async with AsyncSessionLocal() as db:
        result = await ReminderService().scan_due_preferences(
            db,
            now_utc=datetime.now(timezone.utc),
        )
        await db.commit()
        return result
```

- [ ] **Step 5: Run tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest tests/test_reminder_service.py::test_celery_has_reminder_schedule -q
```

Expected: PASS.

- [ ] **Step 6: Smoke test Celery import**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m celery -A app.core.celery_app inspect ping
```

Expected locally: may report no nodes if worker is not running, but import must not crash.

- [ ] **Step 7: Commit**

```bash
git add backend-service/app/core/celery_app.py backend-service/app/tasks/reminders.py backend-service/tests/test_reminder_service.py
git commit -m "feat: schedule fsrs reminder worker"
```

### Task 10: Add local and production process config

**Files:**
- Modify: `docker-compose.yml`
- Modify: `docker-compose.production.yml`
- Modify: `backend-service/render.yaml`

- [ ] **Step 1: Add local worker service**

In `docker-compose.yml`, add:

```yaml
  backend-reminder-worker:
    build:
      context: ./backend-service
      dockerfile: Dockerfile
    command: celery -A app.core.celery_app worker --loglevel=INFO --concurrency=1
    environment:
      DATABASE_URL: postgresql+asyncpg://${POSTGRES_USER:-lexilingo}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-lexilingo}
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY: ${SECRET_KEY:?Set SECRET_KEY in .env}
      REMINDERS_ENABLED: ${REMINDERS_ENABLED:-false}
      REMINDER_DRY_RUN: ${REMINDER_DRY_RUN:-true}
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - lexilingo-network
```

- [ ] **Step 2: Add local beat service**

In `docker-compose.yml`, add:

```yaml
  backend-reminder-beat:
    build:
      context: ./backend-service
      dockerfile: Dockerfile
    command: celery -A app.core.celery_app beat --loglevel=INFO
    environment:
      DATABASE_URL: postgresql+asyncpg://${POSTGRES_USER:-lexilingo}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB:-lexilingo}
      REDIS_URL: redis://redis:6379/0
      SECRET_KEY: ${SECRET_KEY:?Set SECRET_KEY in .env}
      REMINDERS_ENABLED: ${REMINDERS_ENABLED:-false}
      REMINDER_DRY_RUN: ${REMINDER_DRY_RUN:-true}
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - lexilingo-network
```

- [ ] **Step 3: Add production compose services**

Mirror worker and beat in `docker-compose.production.yml`, using `Dockerfile.prod`, `env_file`, and existing production Redis URL.

- [ ] **Step 4: Add Render workers**

In `backend-service/render.yaml`, add two worker services:

```yaml
  - type: worker
    name: lexilingo-reminder-worker
    env: python
    region: singapore
    buildCommand: |
      pip install --upgrade pip
      pip install -r requirements.txt
    startCommand: celery -A app.core.celery_app worker --loglevel=INFO --concurrency=1
    autoDeploy: true
    branch: main
    envVars:
      - key: REMINDERS_ENABLED
        value: "false"
      - key: REMINDER_DRY_RUN
        value: "true"
      - key: DATABASE_URL
        sync: false
      - key: REDIS_URL
        sync: false
      - key: SECRET_KEY
        sync: false

  - type: worker
    name: lexilingo-reminder-beat
    env: python
    region: singapore
    buildCommand: |
      pip install --upgrade pip
      pip install -r requirements.txt
    startCommand: celery -A app.core.celery_app beat --loglevel=INFO
    autoDeploy: true
    branch: main
    envVars:
      - key: REMINDERS_ENABLED
        value: "false"
      - key: REMINDER_DRY_RUN
        value: "true"
      - key: DATABASE_URL
        sync: false
      - key: REDIS_URL
        sync: false
      - key: SECRET_KEY
        sync: false
```

- [ ] **Step 5: Validate process config**

Run:

```bash
docker compose -f docker-compose.yml config >/tmp/lexilingo-compose.yml
docker compose -f docker-compose.production.yml config >/tmp/lexilingo-compose-production.yml
cd backend-service
python -m compileall app/core/celery_app.py app/tasks/reminders.py
```

Expected: both Compose files parse and Celery modules compile. Validate `backend-service/render.yaml` with Render Blueprint preview before production apply.

- [ ] **Step 6: Commit**

```bash
git add docker-compose.yml docker-compose.production.yml backend-service/render.yaml
git commit -m "chore: configure reminder worker processes"
```

---

## Chunk 5: Flutter Settings And Notification UX

### Task 11: Extend settings model safely

**Files:**
- Modify: `flutter-app/lib/features/user/domain/entities/settings.dart`
- Modify: `flutter-app/lib/features/user/data/models/settings_model.dart`
- Modify: `flutter-app/lib/features/user/data/datasources/settings_local_data_source.dart`
- Modify: `flutter-app/lib/features/user/data/datasources/settings_local_data_source_web.dart`
- Modify: `flutter-app/lib/core/services/database_helper.dart`
- Test: `flutter-app/test/features/user/settings_model_test.dart`

- [ ] **Step 1: Write model tests**

Cover:

- old local JSON without new fields still parses
- backend snake_case JSON parses
- `toJson()` preserves old local keys and includes new fields

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd flutter-app
flutter test test/features/user/settings_model_test.dart
```

Expected: FAIL because new fields do not exist.

- [ ] **Step 3: Add fields to `Settings`**

Add defaults:

```dart
final bool pushReminderEnabled;
final bool emailReminderEnabled;
final int emailCadenceDays;
final int reminderMinDueCount;
final String reminderTimezone;
```

Defaults:

- `pushReminderEnabled = true`
- `emailReminderEnabled = false`
- `emailCadenceDays = 7`
- `reminderMinDueCount = 1`
- `reminderTimezone = 'Asia/Ho_Chi_Minh'`

- [ ] **Step 4: Update `SettingsModel` parsing**

Accept both:

- local camelCase: `pushReminderEnabled`
- backend snake_case: `push_enabled`

Map `notificationEnabled` to backend `enabled` when reading remote response.

- [ ] **Step 5: Update local data sources**

Add new fields to create/update payloads. Keep existing keys unchanged.

- [ ] **Step 6: Bump sqflite DB version**

In `flutter-app/lib/core/services/database_helper.dart`, bump `version` from `6` to `7` and add:

```dart
if (oldVersion < 7) {
  await db.execute('ALTER TABLE settings ADD COLUMN pushReminderEnabled BOOLEAN DEFAULT 1');
  await db.execute('ALTER TABLE settings ADD COLUMN emailReminderEnabled BOOLEAN DEFAULT 0');
  await db.execute('ALTER TABLE settings ADD COLUMN emailCadenceDays INTEGER DEFAULT 7');
  await db.execute('ALTER TABLE settings ADD COLUMN reminderMinDueCount INTEGER DEFAULT 1');
  await db.execute('ALTER TABLE settings ADD COLUMN reminderTimezone TEXT DEFAULT "Asia/Ho_Chi_Minh"');
}
```

Also update `_createSettingsTable`.

- [ ] **Step 7: Run model tests**

Run:

```bash
cd flutter-app
flutter test test/features/user/settings_model_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add flutter-app/lib/features/user/domain/entities/settings.dart flutter-app/lib/features/user/data/models/settings_model.dart flutter-app/lib/features/user/data/datasources/settings_local_data_source.dart flutter-app/lib/features/user/data/datasources/settings_local_data_source_web.dart flutter-app/lib/core/services/database_helper.dart flutter-app/test/features/user/settings_model_test.dart
git commit -m "feat: extend reminder settings model"
```

### Task 12: Sync reminder settings with backend

**Files:**
- Create: `flutter-app/lib/features/user/data/datasources/settings_remote_data_source.dart`
- Modify: `flutter-app/lib/features/user/data/repositories/settings_repository_impl.dart`
- Modify: `flutter-app/lib/features/user/domain/repositories/settings_repository.dart`
- Modify: `flutter-app/lib/features/user/di/user_di.dart`
- Modify: `flutter-app/lib/features/user/presentation/providers/settings_provider.dart`
- Test: `flutter-app/test/features/user/settings_provider_reminder_test.dart`

- [ ] **Step 1: Write provider tests**

Cover:

- load settings uses local data when backend is unavailable
- update notification settings persists locally first
- backend update is called with `/users/me/reminder-preferences`
- local fallback notification is scheduled only when backend sync fails or FCM is unavailable

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd flutter-app
flutter test test/features/user/settings_provider_reminder_test.dart
```

Expected: FAIL.

- [ ] **Step 3: Implement remote data source**

Use `ApiClient.get` and `ApiClient.putEnvelope` or `ApiClient.put` depending on existing response helpers:

```dart
class SettingsRemoteDataSource {
  final ApiClient apiClient;

  SettingsRemoteDataSource({required this.apiClient});

  Future<SettingsModel> getReminderPreferences(String userId) async {
    final response = await apiClient.get('/users/me/reminder-preferences');
    return SettingsModel.fromJson(response['data'] as Map<String, dynamic>);
  }

  Future<SettingsModel> updateReminderPreferences(Settings settings) async {
    final response = await apiClient.putEnvelope<Map<String, dynamic>>(
      '/users/me/reminder-preferences',
      body: {
        'enabled': settings.notificationEnabled,
        'push_enabled': settings.pushReminderEnabled,
        'email_enabled': settings.emailReminderEnabled,
        'reminder_time_local': settings.notificationTime,
        'timezone': settings.reminderTimezone,
        'min_due_count': settings.reminderMinDueCount,
        'email_cadence_days': settings.emailCadenceDays,
      },
      fromJson: (json) => json as Map<String, dynamic>,
    );
    return SettingsModel.fromJson(response.data);
  }
}
```

Adjust to the actual `ApiClient` envelope behavior while implementing.

- [ ] **Step 4: Update repository**

Constructor should accept optional `SettingsRemoteDataSource`.

Read flow:

1. Load local settings.
2. Try backend reminder preferences.
3. Merge remote reminder fields into local settings.
4. Save merged local settings.
5. Return merged settings.

Write flow:

1. Save local settings first.
2. Try backend sync.
3. Return success if local save succeeds.
4. Surface a non-fatal warning in debug logs if backend fails.

- [ ] **Step 5: Update provider**

Add:

```dart
Future<void> updateReminderChannels({
  bool? pushEnabled,
  bool? emailEnabled,
  int? emailCadenceDays,
  int? minDueCount,
})
```

Keep existing `updateNotificationSettings({enabled, time})`.

- [ ] **Step 6: Update DI**

Register `SettingsRemoteDataSource(apiClient: sl<ApiClient>())` and pass it into `SettingsRepositoryImpl`.

- [ ] **Step 7: Run tests**

Run:

```bash
cd flutter-app
flutter test test/features/user/settings_provider_reminder_test.dart
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add flutter-app/lib/features/user/data/datasources/settings_remote_data_source.dart flutter-app/lib/features/user/data/repositories/settings_repository_impl.dart flutter-app/lib/features/user/domain/repositories/settings_repository.dart flutter-app/lib/features/user/di/user_di.dart flutter-app/lib/features/user/presentation/providers/settings_provider.dart flutter-app/test/features/user/settings_provider_reminder_test.dart
git commit -m "feat: sync reminder settings with backend"
```

### Task 13: Update settings UI

**Files:**
- Modify: `flutter-app/lib/features/user/presentation/pages/settings_page.dart`
- Modify: all `flutter-app/assets/i18n/*.json`

- [ ] **Step 1: Add UI controls**

Inside `_buildNotificationSettings`, keep the existing daily reminder switch/time row and add:

- push reminder switch
- email reminder switch
- email cadence selector visible when email is enabled
- min due count selector or compact stepper

Suggested labels:

- `settings.reviewReminder`
- `settings.reviewReminderSubtitle`
- `settings.pushReminder`
- `settings.emailReminder`
- `settings.emailCadence`
- `settings.emailCadenceWeekly`
- `settings.emailCadenceEvery3Days`
- `settings.minDueCount`

- [ ] **Step 2: Keep UI non-breaking**

Rules:

- If `notificationEnabled == false`, hide channel controls.
- If backend sync fails, keep local settings and show one non-blocking SnackBar.
- Do not remove current time picker.
- Do not add explanatory paragraphs inside the settings card; use concise row labels.

- [ ] **Step 3: Add i18n keys to all locale files**

Use English fallback translations for non-English files if full localization is not ready.

- [ ] **Step 4: Run Flutter analyze**

Run:

```bash
cd flutter-app
flutter analyze lib/features/user
```

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add flutter-app/lib/features/user/presentation/pages/settings_page.dart flutter-app/assets/i18n
git commit -m "feat: add review reminder settings UI"
```

### Task 14: Route FCM and notification taps to review

**Files:**
- Create: `flutter-app/lib/core/services/app_navigation_service.dart`
- Modify: `flutter-app/lib/main.dart`
- Modify: `flutter-app/lib/core/services/firebase_messaging_service.dart`
- Modify: `flutter-app/lib/features/notifications/domain/entities/notification_entity.dart`
- Modify: `flutter-app/lib/features/notifications/presentation/pages/notifications_page.dart`
- Modify: `flutter-app/lib/features/vocabulary/presentation/widgets/daily_review_card.dart`
- Test: `flutter-app/test/core/services/firebase_messaging_service_test.dart`
- Test: `flutter-app/test/features/notifications/notification_entity_test.dart`

- [ ] **Step 1: Write tests**

Cover:

- `vocabulary_review_reminder` parses to `NotificationType.vocabularyReviewReminder`
- FCM token registration posts to `/devices`, not `/api/devices`
- FCM tap handler recognizes `route=/vocabulary/review`

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
cd flutter-app
flutter test test/core/services/firebase_messaging_service_test.dart test/features/notifications/notification_entity_test.dart
```

Expected: FAIL for path/type gaps.

- [ ] **Step 3: Add navigation service**

Create:

```dart
import 'package:flutter/material.dart';

class AppNavigationService {
  static final navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> openRoute(String route) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    await navigator.pushNamed(route);
  }
}
```

- [ ] **Step 4: Update `MaterialApp`**

In `flutter-app/lib/main.dart`:

```dart
navigatorKey: AppNavigationService.navigatorKey,
```

Add named route:

```dart
'/vocabulary/review': (context) => ChangeNotifierProvider(
  create: (_) => vocab_di.getIt<FlashcardProvider>(),
  child: const FlashcardReviewScreen(),
),
```

Adjust imports.

- [ ] **Step 5: Fix FCM device path**

In `firebase_messaging_service.dart`, change:

```dart
await client.post('/api/devices', body: ...)
```

to:

```dart
await client.post('/devices', body: ...)
```

- [ ] **Step 6: Handle reminder type**

Add `vocabularyReviewReminder` enum value and parse:

```dart
case 'vocabulary_review_reminder':
  return NotificationType.vocabularyReviewReminder;
```

Icon: `style` or `schedule`; color: app primary.

- [ ] **Step 7: Route taps**

In FCM tap handler and notifications page tap handler:

```dart
final route = data['route'] as String?;
if (route == '/vocabulary/review') {
  AppNavigationService.openRoute(route);
  return;
}
```

- [ ] **Step 8: Run tests**

Run:

```bash
cd flutter-app
flutter test test/core/services/firebase_messaging_service_test.dart test/features/notifications/notification_entity_test.dart
flutter analyze lib/core/services lib/features/notifications lib/features/vocabulary
```

Expected: PASS and no analyzer issues.

- [ ] **Step 9: Commit**

```bash
git add flutter-app/lib/core/services/app_navigation_service.dart flutter-app/lib/main.dart flutter-app/lib/core/services/firebase_messaging_service.dart flutter-app/lib/features/notifications/domain/entities/notification_entity.dart flutter-app/lib/features/notifications/presentation/pages/notifications_page.dart flutter-app/lib/features/vocabulary/presentation/widgets/daily_review_card.dart flutter-app/test/core/services/firebase_messaging_service_test.dart flutter-app/test/features/notifications/notification_entity_test.dart
git commit -m "feat: open vocabulary review from reminders"
```

---

## Chunk 6: Verification And Rollout

### Task 15: End-to-end backend verification

**Files:**
- No production file changes unless tests reveal defects.

- [ ] **Step 1: Run focused backend tests**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false ../venv/bin/python -m pytest \
  tests/test_vocabulary_fsrs.py \
  tests/test_vocabulary_routes.py \
  tests/test_devices_routes.py \
  tests/test_reminder_preferences_routes.py \
  tests/test_notifications_routes.py \
  tests/test_fsrs_scheduler_service.py \
  tests/test_reminder_service.py \
  tests/test_push_notification_service.py \
  tests/test_email_service_review_reminder.py \
  -q
```

Expected: all pass.

- [ ] **Step 2: Run Alembic upgrade on test database**

Run:

```bash
cd backend-service
APP_ENV=testing DEBUG=false alembic upgrade head
```

Expected: migration succeeds.

- [ ] **Step 3: Run worker dry-run locally**

Run Redis/Postgres, then:

```bash
cd backend-service
REMINDERS_ENABLED=true REMINDER_DRY_RUN=true celery -A app.core.celery_app worker --loglevel=INFO --concurrency=1
```

In another shell:

```bash
cd backend-service
REMINDERS_ENABLED=true REMINDER_DRY_RUN=true celery -A app.core.celery_app call app.tasks.reminders.scan_fsrs_reminders
```

Expected: task completes and logs dry-run/skipped deliveries without sending FCM or email.

- [ ] **Step 4: Commit fixes if needed**

Only commit if verification required code changes.

### Task 16: End-to-end Flutter verification

**Files:**
- No production file changes unless tests reveal defects.

- [ ] **Step 1: Run focused Flutter tests**

Run:

```bash
cd flutter-app
flutter test \
  test/features/user/settings_model_test.dart \
  test/features/user/settings_provider_reminder_test.dart \
  test/core/services/firebase_messaging_service_test.dart \
  test/features/notifications/notification_entity_test.dart \
  test/smoke/vocab_and_lexi_offline_smoke_test.dart
```

Expected: all pass.

- [ ] **Step 2: Run analyzer**

Run:

```bash
cd flutter-app
flutter analyze lib/features/user lib/features/notifications lib/core/services lib/features/vocabulary
```

Expected: no issues.

- [ ] **Step 3: Manual UI verification**

Run app and verify:

- Settings page still opens for an existing user.
- Existing daily reminder toggle/time remain visible.
- New push/email controls appear only when reminders are enabled.
- Saving settings does not block the UI if backend is offline.
- Notification tap opens vocabulary review screen.
- Flashcard review still submits ratings and updates due count.

### Task 17: Production rollout

**Files:**
- Deployment environment only.

- [ ] **Step 1: Deploy API with feature off**

Set:

```env
REMINDERS_ENABLED=false
REMINDER_DRY_RUN=true
```

Deploy migration and API first.

- [ ] **Step 2: Deploy worker and beat with dry-run**

Start worker and beat with the same env. Confirm logs show scans but no sends.

- [ ] **Step 3: Enable one test user**

Use API to enable reminder preference for a test user with due vocabulary. Keep:

```env
REMINDER_DRY_RUN=true
```

Expected: delivery rows show dry-run/skipped status.

- [ ] **Step 4: Enable live push for test user**

Set:

```env
REMINDERS_ENABLED=true
REMINDER_DRY_RUN=false
```

Expected:

- one `notifications` row
- one push delivery row
- no duplicate push for same local day/channel

- [ ] **Step 5: Enable email for test user**

Set SMTP env vars if absent. Confirm one email delivery and email cadence prevents a second email inside the configured period.

- [ ] **Step 6: Broaden rollout**

Keep monitoring:

- Celery worker logs
- `reminder_deliveries.status`
- FCM failure rate
- SMTP failure rate
- duplicate delivery count
- user unsubscribe/settings changes

### Task 18: Update project checklist

**Files:**
- Modify: `docs/Checklist_Vocabulary_Speak.md`

- [ ] **Step 1: Add reminder scheduler section**

Add a new unchecked section linking this plan.

- [ ] **Step 2: Commit**

```bash
git add docs/Checklist_Vocabulary_Speak.md docs/superpowers/plans/2026-06-01-fsrs-reminder-scheduler.md
git commit -m "docs: plan fsrs reminder scheduler"
```

---

## Acceptance Criteria

- Existing vocabulary review endpoints and tests still pass.
- Existing local settings load for old users without migration crashes.
- Backend reminder preferences are user-configurable through Settings.
- Celery beat triggers a queue task instead of running scheduler logic inside FastAPI.
- Worker sends reminders only when `REMINDERS_ENABLED=true`.
- Dry-run mode never sends FCM or SMTP.
- Reminder delivery is idempotent per user, local date, and channel.
- FSRS due reminders are based on `user_vocabulary.next_review_date <= now`.
- Email reminders respect user cadence and default to off.
- FCM push payload includes `type=vocabulary_review_reminder`, `route=/vocabulary/review`, and `due_count`.
- Notification page and push taps can open the vocabulary review flow.

## Rollback Plan

- Set `REMINDERS_ENABLED=false` to stop sending immediately.
- Stop `lexilingo-reminder-worker` and `lexilingo-reminder-beat`.
- Keep new tables in place; they are additive and do not affect existing API reads.
- If Flutter settings sync causes issues, disable backend reminder API calls in the repository while keeping local settings behavior.
- Do not downgrade Alembic unless absolutely required; the migration only adds tables.

## Notes For Implementers

- This plan intentionally avoids changing the FSRS scheduling formula during reminder rollout. The reminder system reads the schedule already produced by reviews.
- If strict official FSRS parity is required later, create a separate plan to add an `FSRS_PROVIDER` adapter and migrate behavior behind a feature flag.
- Run @requesting-code-review after Chunk 4 and Chunk 6 because the worker can create duplicate external side effects if idempotency is wrong.

Plan complete and saved to `docs/superpowers/plans/2026-06-01-fsrs-reminder-scheduler.md`. Ready to execute?
