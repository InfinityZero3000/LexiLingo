---
name: schema-pydantic-v2-conventions
description: Pydantic v2 schema conventions for LexiLingo. Use Field(...) for required fields, Field(default=...) for optional, model_dump(exclude_unset=True) for PATCH updates. All response schemas in app/schemas/<feature>.py.
impact: HIGH
---

# Pydantic v2 Schema Conventions

## Context

LexiLingo uses Pydantic v2 throughout. The key differences from v1: `model_dump()` replaces `.dict()`, `model_validate()` replaces `parse_obj()`, and validators use `@field_validator` / `@model_validator`.

## Correct Schema Pattern

```python
# app/schemas/notification.py
"""
Notification Schemas

Request and response models for notifications endpoints.
"""

from datetime import datetime
from typing import Optional, Literal
from pydantic import BaseModel, Field


class NotificationResponse(BaseModel):
    """Single notification response."""
    id: str
    type: Literal["streak", "review", "achievement", "system"]
    title: str
    body: str
    created_at: datetime
    is_read: bool = False
    data: Optional[dict] = None

    model_config = {"from_attributes": True}  # enables ORM mode


class NotificationListResponse(BaseModel):
    """Paginated notification list response."""
    notifications: list[NotificationResponse]
    unread_count: int
    total: int


class MarkAsReadRequest(BaseModel):
    """Request body for marking notifications as read."""
    notification_ids: list[str] = Field(
        ...,
        min_length=1,
        description="List of notification IDs to mark as read",
    )
```

## Update Pattern (PATCH — exclude_unset)

```python
# For endpoints that partially update a resource:
class UserUpdate(BaseModel):
    display_name: Optional[str] = Field(None, max_length=100)
    avatar_url: Optional[str] = None
    daily_goal_minutes: Optional[int] = Field(None, ge=5, le=480)

# In route:
update_dict = update_data.model_dump(exclude_unset=True)  # only fields sent by client
for field, value in update_dict.items():
    setattr(current_user, field, value)
await db.commit()
```

## Field Guidelines

```python
# Required field
name: str = Field(..., description="Display name")

# Optional with default
streak: int = Field(default=0, ge=0)

# Constrained string
level_code: str = Field(..., pattern=r'^(A1|A2|B1|B2|C1|C2)$')

# Constrained number
xp: int = Field(..., ge=0, le=1_000_000)

# DateTime — always use datetime, never str for dates in API responses
created_at: datetime  # FastAPI serializes to ISO 8601 automatically
```

## Naming Convention

| Backend (snake_case) | Flutter receives (snake_case JSON) | Dart camelCase |
|----------------------|------------------------------------|----------------|
| `total_xp` | `total_xp` | `totalXP` |
| `is_read` | `is_read` | `isRead` |
| `created_at` | `created_at` | `createdAt` |
| `weekly_activity` | `weekly_activity` | `weeklyActivity` |

**Always use snake_case** in Pydantic models — Flutter data models do the camelCase mapping.

## Incorrect Pattern

```python
# Anti-pattern: mixing v1 style
class UserStats(BaseModel):
    class Config:
        orm_mode = True  # ❌ Pydantic v1 style

# Anti-pattern: returning raw dict in response
@router.get("/me/stats")
async def stats():
    return {"total_xp": 1200}  # ❌ not typed, no validation

# Anti-pattern: camelCase field names in schema
class NotificationResponse(BaseModel):
    isRead: bool  # ❌ use is_read
```
