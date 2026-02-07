"""
User Management Routes (Admin Panel - Phase 2)
Provides user CRUD operations, role management, and activity tracking.
"""
from datetime import datetime, timedelta
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, Query, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select, func, or_, and_, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas.response import ApiResponse
from app.core.dependencies import get_current_admin, get_current_super_admin
from app.models.user import User
from app.models.rbac import Role
from app.models.progress import DailyActivity, LessonCompletion, UserCourseProgress


router = APIRouter(prefix="/admin/users", tags=["Admin - User Management"])


# ============================================================================
# Request/Response Models
# ============================================================================

class UserListResponse(BaseModel):
    """User list response with metadata"""
    id: str
    email: str
    username: str
    display_name: Optional[str] = None
    is_active: bool
    is_verified: bool
    role_slug: str  # user, admin, super_admin
    role_level: int  # 0, 1, 2
    created_at: datetime
    last_login: Optional[datetime] = None
    
    class Config:
        from_attributes = True


class UserDetailResponse(BaseModel):
    """Detailed user information"""
    id: str
    email: str
    username: str
    display_name: Optional[str] = None
    avatar_url: Optional[str] = None
    is_active: bool
    is_verified: bool
    role_slug: str  # user, admin, super_admin
    role_level: int  # 0, 1, 2
    provider: str  # local, google, facebook
    created_at: datetime
    last_login: Optional[datetime] = None
    total_xp: int = 0
    
    # Stats
    courses_enrolled: int = 0
    courses_completed: int = 0
    lessons_completed: int = 0
    daily_activities: int = 0
    
    class Config:
        from_attributes = True


class UserUpdateRequest(BaseModel):
    """Admin can update user information"""
    display_name: Optional[str] = Field(None, max_length=100)
    is_active: Optional[bool] = None


class RoleUpdateRequest(BaseModel):
    """Update user role (admin level)"""
    level: int = Field(..., ge=0, le=2, description="0=user, 1=admin, 2=super_admin")


class StatusUpdateRequest(BaseModel):
    """Update user status"""
    is_active: bool


class BulkActionRequest(BaseModel):
    """Bulk operations on users"""
    user_ids: List[str]
    action: str = Field(..., description="activate, deactivate, delete")


class ActivityLogResponse(BaseModel):
    """User activity log entry"""
    activity_date: str
    activity_type: str
    description: str
    xp_earned: int = 0
    
    class Config:
        from_attributes = True


class PaginatedUsersResponse(BaseModel):
    """Paginated user list"""
    users: List[UserListResponse]
    total: int
    page: int
    page_size: int
    total_pages: int


# ============================================================================
# User List & Search
# ============================================================================

@router.get("", response_model=ApiResponse[PaginatedUsersResponse])
async def list_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    search: Optional[str] = Query(None, description="Search by name or email"),
    role: Optional[int] = Query(None, ge=0, le=2, description="Filter by role level"),
    is_active: Optional[bool] = Query(None, description="Filter by active status"),
    sort_by: str = Query("created_at", pattern="^(created_at|last_login|email|role|total_xp)$"),
    order: str = Query("desc", pattern="^(asc|desc)$"),
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    List all users with pagination, filtering, and sorting.
    
    **Filters:**
    - search: Search in email and display_name
    - role: 0=user, 1=admin, 2=super_admin
    - is_active: true/false
    
    **Sort options:**
    - created_at, last_login, email, role, total_xp
    """
    # Build query with Role join for filtering/sorting
    query = select(User).join(User.role)
    
    # Apply filters
    filters = []
    if search:
        search_pattern = f"%{search}%"
        filters.append(
            or_(
                User.email.ilike(search_pattern),
                User.display_name.ilike(search_pattern)
            )
        )
    
    if role is not None:
        filters.append(Role.level == role)
    
    if is_active is not None:
        filters.append(User.is_active == is_active)
    
    if filters:
        query = query.where(and_(*filters))
    
    # Apply sorting
    if sort_by == "role":
        sort_column = Role.level
    else:
        sort_column = getattr(User, sort_by)
    
    if order == "desc":
        query = query.order_by(desc(sort_column))
    else:
        query = query.order_by(sort_column)
    
    # Get total count
    count_query = select(func.count()).select_from(query.subquery())
    total = await db.scalar(count_query) or 0
    
    # Apply pagination
    offset = (page - 1) * page_size
    query = query.offset(offset).limit(page_size)
    
    # Execute query
    result = await db.execute(query)
    users = result.scalars().all()
    
    # Convert to response model
    users_list = [
        UserListResponse(
            id=str(user.id),
            email=user.email,
            username=user.username,
            display_name=user.display_name or user.username,
            is_active=user.is_active,
            is_verified=user.is_verified,
            role_slug=user.role_slug,
            role_level=user.role_level,
            created_at=user.created_at,
            last_login=user.last_login,
        )
        for user in users
    ]
    
    total_pages = (total + page_size - 1) // page_size
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(users_list)} users",
        data=PaginatedUsersResponse(
            users=users_list,
            total=total,
            page=page,
            page_size=page_size,
            total_pages=total_pages,
        )
    )


# ============================================================================
# User Detail
# ============================================================================

@router.get("/{user_id}", response_model=ApiResponse[UserDetailResponse])
async def get_user_detail(
    user_id: UUID,
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get detailed information about a specific user.
    """
    # Get user
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Get stats
    courses_enrolled = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(UserCourseProgress.user_id == user_id)
    ) or 0
    
    courses_completed = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(
            and_(
                UserCourseProgress.user_id == user_id,
                UserCourseProgress.progress_percentage >= 100
            )
        )
    ) or 0
    
    lessons_completed = await db.scalar(
        select(func.count(LessonCompletion.id))
        .where(LessonCompletion.user_id == user_id)
    ) or 0
    
    daily_activities = await db.scalar(
        select(func.count(DailyActivity.id))
        .where(DailyActivity.user_id == user_id)
    ) or 0
    
    return ApiResponse(
        success=True,
        message="User details retrieved successfully",
        data=UserDetailResponse(
            id=str(user.id),
            email=user.email,
            username=user.username,
            display_name=user.display_name or user.username,
            avatar_url=user.avatar_url,
            is_active=user.is_active,
            is_verified=user.is_verified,
            role_slug=user.role_slug,
            role_level=user.role_level,
            provider=user.provider,
            created_at=user.created_at,
            last_login=user.last_login,
            total_xp=user.total_xp,
            courses_enrolled=courses_enrolled,
            courses_completed=courses_completed,
            lessons_completed=lessons_completed,
            daily_activities=daily_activities,
        )
    )


# ============================================================================
# User Update
# ============================================================================

@router.put("/{user_id}", response_model=ApiResponse[UserDetailResponse])
async def update_user(
    user_id: UUID,
    data: UserUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Update user information (basic profile fields).
    
    **Permissions:**
    - Admins can update basic info and activate/deactivate
    - Use separate endpoint to change user roles
    """
    # Get user
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Update fields
    if data.display_name is not None:
        user.display_name = data.display_name
    
    if data.is_active is not None:
        user.is_active = data.is_active
    
    await db.commit()
    await db.refresh(user)
    
    # Get stats for response
    courses_enrolled = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(UserCourseProgress.user_id == user_id)
    ) or 0
    
    courses_completed = await db.scalar(
        select(func.count(UserCourseProgress.id))
        .where(
            and_(
                UserCourseProgress.user_id == user_id,
                UserCourseProgress.progress_percentage >= 100
            )
        )
    ) or 0
    
    lessons_completed = await db.scalar(
        select(func.count(LessonCompletion.id))
        .where(LessonCompletion.user_id == user_id)
    ) or 0
    
    daily_activities = await db.scalar(
        select(func.count(DailyActivity.id))
        .where(DailyActivity.user_id == user_id)
    ) or 0
    
    return ApiResponse(
        success=True,
        message="User updated successfully",
        data=UserDetailResponse(
            id=str(user.id),
            email=user.email,
            username=user.username,
            display_name=user.display_name or user.username,
            avatar_url=user.avatar_url,
            is_active=user.is_active,
            is_verified=user.is_verified,
            role_slug=user.role_slug,
            role_level=user.role_level,
            provider=user.provider,
            created_at=user.created_at,
            last_login=user.last_login,
            total_xp=user.total_xp,
            courses_enrolled=courses_enrolled,
            courses_completed=courses_completed,
            lessons_completed=lessons_completed,
            daily_activities=daily_activities,
        )
    )


# ============================================================================
# Role Management
# ============================================================================

@router.put("/{user_id}/role")
async def update_user_role(
    user_id: UUID,
    data: RoleUpdateRequest,
    admin: User = Depends(get_current_super_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Update user role (super_admin only).
    
    **Levels:**
    - 0: Regular user
    - 1: Admin
    - 2: Super Admin
    """
    # Get user
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Prevent self-demotion
    if user.id == admin.id and data.level < admin.role_level:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot demote yourself"
        )
    
    # Find role by level
    role_result = await db.execute(
        select(Role).where(Role.level == data.level)
    )
    new_role = role_result.scalar_one_or_none()
    
    if not new_role:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Role with level {data.level} not found"
        )
    
    user.role_id = new_role.id
    await db.commit()
    await db.refresh(user)
    
    return ApiResponse(
        success=True,
        message="User role updated successfully",
        data={
            "user_id": str(user.id),
            "new_level": data.level,
            "new_role": user.role_slug
        }
    )


# ============================================================================
# Status Management
# ============================================================================

@router.put("/{user_id}/status")
async def update_user_status(
    user_id: UUID,
    data: StatusUpdateRequest,
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Activate or deactivate a user account.
    """
    # Get user
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Prevent self-deactivation
    if user.id == admin.id and not data.is_active:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot deactivate your own account"
        )
    
    user.is_active = data.is_active
    await db.commit()
    
    return ApiResponse(
        success=True,
        message=f"User {'activated' if data.is_active else 'deactivated'} successfully",
        data={
            "user_id": str(user.id),
            "is_active": data.is_active
        }
    )


# ============================================================================
# User Activity Timeline
# ============================================================================

@router.get("/{user_id}/activity", response_model=ApiResponse[List[ActivityLogResponse]])
async def get_user_activity(
    user_id: UUID,
    days: int = Query(30, ge=1, le=365),
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Get user activity timeline for the last N days.
    
    Shows:
    - Daily activities (login, lessons completed)
    - Course enrollments
    - Achievements
    """
    # Check user exists
    result = await db.execute(
        select(User).where(User.id == user_id)
    )
    user = result.scalar_one_or_none()
    
    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )
    
    # Get activity from last N days
    start_date = datetime.utcnow() - timedelta(days=days)
    
    # Daily activities
    activities_result = await db.execute(
        select(DailyActivity)
        .where(
            and_(
                DailyActivity.user_id == user_id,
                DailyActivity.activity_date >= start_date.date()
            )
        )
        .order_by(desc(DailyActivity.activity_date))
    )
    activities = activities_result.scalars().all()
    
    # Convert to response
    activity_log = []
    
    for activity in activities:
        activity_log.append(
            ActivityLogResponse(
                activity_date=activity.activity_date.isoformat(),
                activity_type="daily_activity",
                description=f"Completed {activity.lessons_completed} lessons, earned {activity.xp_earned} XP",
                xp_earned=activity.xp_earned,
            )
        )
    
    # Lesson completions
    lessons_result = await db.execute(
        select(LessonCompletion)
        .where(
            and_(
                LessonCompletion.user_id == user_id,
                LessonCompletion.completed_at >= start_date
            )
        )
        .order_by(desc(LessonCompletion.completed_at))
        .limit(50)
    )
    lessons = lessons_result.scalars().all()
    
    for lesson in lessons:
        activity_log.append(
            ActivityLogResponse(
                activity_date=lesson.completed_at.isoformat() if lesson.completed_at else "",
                activity_type="lesson_completed",
                description=f"Completed lesson (Score: {lesson.score}%)",
                xp_earned=lesson.xp_earned,
            )
        )
    
    # Sort by date descending
    activity_log.sort(key=lambda x: x.activity_date, reverse=True)
    
    return ApiResponse(
        success=True,
        message=f"Retrieved {len(activity_log)} activity logs",
        data=activity_log
    )


# ============================================================================
# Bulk Operations
# ============================================================================

@router.post("/bulk-action")
async def bulk_user_action(
    data: BulkActionRequest,
    admin: User = Depends(get_current_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Perform bulk operations on multiple users.
    
    **Actions:**
    - activate: Activate selected users
    - deactivate: Deactivate selected users
    - delete: Soft delete selected users (requires super_admin)
    """
    if not data.user_ids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No user IDs provided"
        )
    
    # Convert string IDs to UUIDs
    try:
        user_uuids = [UUID(uid) for uid in data.user_ids]
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid user ID format"
        )
    
    # Prevent self-action
    if admin.id in user_uuids:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot perform bulk action on your own account"
        )
    
    # Get users
    result = await db.execute(
        select(User).where(User.id.in_(user_uuids))
    )
    users = result.scalars().all()
    
    if not users:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No users found with provided IDs"
        )
    
    # Perform action
    updated_count = 0
    
    if data.action == "activate":
        for user in users:
            user.is_active = True
            updated_count += 1
    
    elif data.action == "deactivate":
        for user in users:
            user.is_active = False
            updated_count += 1
    
    elif data.action == "delete":
        # Require super_admin for deletion
        if admin.role_level < 2:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Only super_admins can delete users"
            )
        
        for user in users:
            user.is_active = False
            # In a real app, you might mark as deleted or actually delete
            updated_count += 1
    
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Unknown action: {data.action}"
        )
    
    await db.commit()
    
    return ApiResponse(
        success=True,
        message=f"Bulk {data.action} completed",
        data={
            "updated_count": updated_count,
            "requested_count": len(data.user_ids)
        }
    )
