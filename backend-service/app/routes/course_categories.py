"""
Course Category API Routes

Endpoints for managing course categories and browsing courses by category.
"""

from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_current_user_optional
from app.models.user import User
from app.crud.course_category import CourseCategoryCRUD
from app.schemas.course_category import (
    CourseCategoryResponse,
    CourseCategoryListItem,
    CourseCategoryCreate,
    CourseCategoryUpdate
)
from app.schemas.course import CourseListItem
from app.schemas.common import ApiResponse, PaginatedResponse, PaginationMeta

router = APIRouter(tags=["course-categories"])


# =====================
# Public Endpoints
# =====================

@router.get("", response_model=ApiResponse[list[CourseCategoryListItem]])
async def get_categories(
    active_only: bool = Query(True, description="Only show active categories"),
    db: AsyncSession = Depends(get_db)
):
    """
    Get all course categories.
    
    - **active_only**: Filter to only show active categories (default: true)
    
    Returns list of categories ordered by order_index.
    """
    categories, _ = await CourseCategoryCRUD.get_all_categories(
        db,
        active_only=active_only,
        skip=0,
        limit=100  # Get all for now
    )
    
    category_items = [
        CourseCategoryListItem.model_validate(cat) for cat in categories
    ]
    
    return ApiResponse(
        success=True,
        data=category_items,
        message="Categories retrieved successfully"
    )


@router.get("/{category_id}", response_model=ApiResponse[CourseCategoryResponse])
async def get_category(
    category_id: uuid.UUID,
    db: AsyncSession = Depends(get_db)
):
    """Get detailed information about a specific category."""
    category = await CourseCategoryCRUD.get_category_by_id(db, category_id)
    
    if not category:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    
    return ApiResponse(
        success=True,
        data=CourseCategoryResponse.model_validate(category),
        message="Category retrieved successfully"
    )


@router.get("/slug/{slug}", response_model=ApiResponse[CourseCategoryResponse])
async def get_category_by_slug(
    slug: str,
    db: AsyncSession = Depends(get_db)
):
    """Get category by slug."""
    category = await CourseCategoryCRUD.get_category_by_slug(db, slug)
    
    if not category:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    
    return ApiResponse(
        success=True,
        data=CourseCategoryResponse.model_validate(category),
        message="Category retrieved successfully"
    )


@router.get("/{category_id}/courses", response_model=PaginatedResponse[CourseListItem])
async def get_courses_by_category(
    category_id: uuid.UUID,
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional)
):
    """
    Get all courses in a specific category.
    
    - **page**: Page number (default: 1)
    - **page_size**: Items per page (default: 20, max: 100)
    
    Returns courses with enrollment status if user is authenticated.
    """
    # Verify category exists
    category = await CourseCategoryCRUD.get_category_by_id(db, category_id)
    if not category:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    
    skip = (page - 1) * page_size
    courses, total = await CourseCategoryCRUD.get_courses_by_category(
        db,
        category_id=category_id,
        skip=skip,
        limit=page_size
    )
    
    # Convert to response models
    from app.crud.course import CourseCRUD
    course_items = []
    for course in courses:
        item_dict = {
            "id": course.id,
            "title": course.title,
            "description": course.description,
            "language": course.language,
            "level": course.level,
            "tags": course.tags or [],
            "thumbnail_url": course.thumbnail_url,
            "total_lessons": course.total_lessons,
            "total_xp": course.total_xp,
            "estimated_duration": course.estimated_duration,
            "is_enrolled": None
        }
        
        item = CourseListItem(**item_dict)
        
        # Add enrollment status if user is authenticated
        if current_user:
            item.is_enrolled = await CourseCRUD.is_user_enrolled(
                db, current_user.id, course.id
            )
        
        course_items.append(item)
    
    # Calculate pagination
    total_pages = (total + page_size - 1) // page_size
    
    return PaginatedResponse(
        data=course_items,
        pagination=PaginationMeta(
            page=page,
            page_size=page_size,
            total=total,
            total_pages=total_pages
        )
    )


# =====================
# Admin Endpoints (Protected)
# =====================

@router.post("", response_model=ApiResponse[CourseCategoryResponse], status_code=status.HTTP_201_CREATED)
async def create_category(
    category_data: CourseCategoryCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Create a new course category.
    
    **Admin only** - Requires authentication.
    """
    # TODO: Add admin role check
    
    # Check if slug already exists
    existing = await CourseCategoryCRUD.get_category_by_slug(db, category_data.slug)
    if existing:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Category with this slug already exists"
        )
    
    category = await CourseCategoryCRUD.create_category(
        db,
        name=category_data.name,
        slug=category_data.slug,
        description=category_data.description,
        icon=category_data.icon,
        color=category_data.color,
        order_index=category_data.order_index,
        is_active=category_data.is_active
    )
    
    return ApiResponse(
        success=True,
        data=CourseCategoryResponse.model_validate(category),
        message="Category created successfully"
    )


@router.put("/{category_id}", response_model=ApiResponse[CourseCategoryResponse])
async def update_category(
    category_id: uuid.UUID,
    update_data: CourseCategoryUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Update a course category.
    
    **Admin only** - Requires authentication.
    """
    # TODO: Add admin role check
    
    # Check if slug is being changed and if it's already taken
    if update_data.slug:
        existing = await CourseCategoryCRUD.get_category_by_slug(db, update_data.slug)
        if existing and existing.id != category_id:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Category with this slug already exists"
            )
    
    update_dict = update_data.model_dump(exclude_unset=True)
    category = await CourseCategoryCRUD.update_category(db, category_id, **update_dict)
    
    if not category:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    
    return ApiResponse(
        success=True,
        data=CourseCategoryResponse.model_validate(category),
        message="Category updated successfully"
    )


@router.delete("/{category_id}", response_model=ApiResponse[dict])
async def delete_category(
    category_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Delete a course category (soft delete).
    
    **Admin only** - Requires authentication.
    """
    # TODO: Add admin role check
    
    success = await CourseCategoryCRUD.delete_category(db, category_id)
    
    if not success:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Category not found"
        )
    
    return ApiResponse(
        success=True,
        data={"id": str(category_id)},
        message="Category deleted successfully"
    )


@router.post("/update-counts", response_model=ApiResponse[dict])
async def update_course_counts(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Update course counts for all categories.
    
    **Admin only** - Should be called periodically or after course changes.
    """
    # TODO: Add admin role check
    
    await CourseCategoryCRUD.update_course_counts(db)
    
    return ApiResponse(
        success=True,
        data={"status": "completed"},
        message="Course counts updated successfully"
    )
