---
name: route-apiresponse-envelope
description: Every endpoint returns ApiResponse[T]. Successful responses use data= + message=. Errors use HTTPException(status_code, detail=). Never return raw dicts or bare Pydantic models.
impact: CRITICAL
---

# ApiResponse[T] Envelope Pattern

## Context

All LexiLingo API endpoints use a consistent JSON envelope: `{ "data": ..., "message": "...", "success": true }`. This allows Flutter clients to always parse the same shape regardless of endpoint.

## The Envelope Schema

```python
# app/schemas/common.py
class ApiResponse(BaseModel, Generic[DataT]):
    success: bool = True
    message: str = ""
    data: Optional[DataT] = None
    meta: Optional[RequestMeta] = None
```

## Correct Route Pattern

```python
# app/routes/users.py
import logging
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.common import ApiResponse
from app.schemas.level import UserStatsResponse
from app.services.level_service import LevelService

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/me/stats", response_model=ApiResponse[UserStatsResponse])
async def get_user_stats(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ApiResponse[UserStatsResponse]:
    """
    Get comprehensive learning statistics for the current user.
    
    Returns streak, XP, level, words learned, study time, and course stats.
    """
    try:
        stats = await LevelService.get_user_stats(db=db, user=current_user)
        return ApiResponse(
            data=stats,
            message="User stats retrieved successfully",
        )
    except Exception as e:
        logger.error("Error fetching user stats for user %s: %s", current_user.id, e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve user statistics",
        )
```

## New Endpoint Checklist

When adding a new `GET /api/users/me/<resource>` endpoint:

1. Add `@router.get(...)` with `response_model=ApiResponse[YourResponseSchema]`
2. Always inject `current_user: User = Depends(get_current_user)`
3. Always inject `db: AsyncSession = Depends(get_db)`
4. Delegate business logic to a service class — never query DB directly in route
5. Wrap in `try/except Exception`, log the error, raise `HTTPException` on failure
6. Return `ApiResponse(data=result, message="<resource> retrieved successfully")`

## Register New Router in main.py

```python
# app/main.py — add to include_router calls
from app.routes.notifications import router as notifications_router

app.include_router(notifications_router, prefix="/api/notifications", tags=["Notifications"])
```

## Incorrect Pattern

```python
# Anti-pattern: returning raw dict
@router.get("/me/stats")
async def get_stats():
    return {"streak": 5, "xp": 1200}  # ❌ no envelope

# Anti-pattern: DB queries in route
@router.get("/me/stats")
async def get_stats(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User))  # ❌ should be in service
    return result

# Anti-pattern: sync DB call
@router.get("/me/stats")
def get_stats(db: Session = Depends(get_db)):  # ❌ sync Session
    return db.query(User).first()
```
