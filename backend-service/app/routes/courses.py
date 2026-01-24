"""
Course API Routes

Endpoints for course management, enrollment, and browsing.
Supports pagination, filtering, and user-specific data.
"""

from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user, get_current_user_optional
from app.models.user import User
from app.models.progress import UserCourseProgress
from app.crud.course import CourseCRUD, UnitCRUD, LessonCRUD
from app.schemas.course import (
    CourseResponse,
    CourseListItem,
    CourseDetailResponse,
    EnrollmentResponse,
    UnitWithLessons,
    LessonInUnit
)
from app.schemas.common import ApiResponse, PaginatedResponse, PaginationMeta
import uuid
from datetime import datetime

router = APIRouter(prefix="/courses", tags=["courses"])


# =====================
# Course Browsing (Public/Authenticated)
# =====================

@router.get("", response_model=PaginatedResponse[list[CourseListItem]])
async def get_courses(
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    language: Optional[str] = Query(None, description="Filter by language (e.g., 'en', 'vi')"),
    level: Optional[str] = Query(None, description="Filter by CEFR level (A1-C2)"),
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional)
):
    """
    Get paginated list of courses.
    
    - **page**: Page number (default: 1)
    - **page_size**: Items per page (default: 20, max: 100)
    - **language**: Filter by language code
    - **level**: Filter by CEFR level (A1, A2, B1, B2, C1, C2)
    
    Returns enrollment status if user is authenticated.
    """
    skip = (page - 1) * page_size
    courses, total = await CourseCRUD.get_courses(
        db,
        skip=skip,
        limit=page_size,
        language=language,
        level=level,
        published_only=True
    )
    
    # Convert to response models
    course_items = []
    for course in courses:
        item = CourseListItem.model_validate(course)
        
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


@router.get("/{course_id}", response_model=ApiResponse[CourseDetailResponse])
async def get_course(
    course_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: Optional[User] = Depends(get_current_user_optional)
):
    """
    Get detailed course information including units and lessons.
    
    - Shows lesson lock status based on prerequisites
    - Shows completion status if user is authenticated
    """
    # Get course with all units and lessons
    course = await CourseCRUD.get_course_with_units(db, course_id)
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found"
        )
    
    if not course.is_published:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not available"
        )
    
    # Build response
    course_response = CourseResponse.model_validate(course)
    
    # Add enrollment info if user is authenticated
    if current_user:
        course_response.is_enrolled = await CourseCRUD.is_user_enrolled(
            db, current_user.id, course.id
        )
    
    # Build units with lessons
    units_with_lessons = []
    for unit in sorted(course.units, key=lambda u: u.order_index):
        lessons = []
        for lesson in sorted(unit.lessons, key=lambda l: l.order_index):
            lesson_data = LessonInUnit.model_validate(lesson)
            
            # Check if lesson is locked (prerequisites not met)
            if current_user and lesson.prerequisites:
                prerequisites_met = True
                for prereq_id in lesson.prerequisites:
                    if not await LessonCRUD.is_lesson_completed(db, current_user.id, prereq_id):
                        prerequisites_met = False
                        break
                lesson_data.is_locked = not prerequisites_met
            else:
                lesson_data.is_locked = bool(lesson.prerequisites)  # Locked if has prerequisites
            
            # Check if lesson is completed
            if current_user:
                lesson_data.is_completed = await LessonCRUD.is_lesson_completed(
                    db, current_user.id, lesson.id
                )
            
            lessons.append(lesson_data)
        
        unit_with_lessons = UnitWithLessons(
            id=unit.id,
            title=unit.title,
            description=unit.description,
            order_index=unit.order_index,
            background_color=unit.background_color,
            icon_url=unit.icon_url,
            lessons=lessons
        )
        units_with_lessons.append(unit_with_lessons)
    
    # Create detailed response
    course_detail = CourseDetailResponse(
        **course_response.model_dump(),
        units=units_with_lessons
    )
    
    return ApiResponse(data=course_detail)


@router.post("/{course_id}/enroll", response_model=ApiResponse[EnrollmentResponse])
async def enroll_in_course(
    course_id: uuid.UUID,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Enroll the current user in a course.
    
    - Creates UserCourseProgress entry
    - Idempotent: returns success if already enrolled
    """
    # Check if course exists
    course = await CourseCRUD.get_course(db, course_id)
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found"
        )
    
    if not course.is_published:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Course not available for enrollment"
        )
    
    # Check if already enrolled
    is_enrolled = await CourseCRUD.is_user_enrolled(db, current_user.id, course_id)
    if is_enrolled:
        return ApiResponse(
            data=EnrollmentResponse(
                course_id=course_id,
                user_id=current_user.id,
                enrolled_at=datetime.utcnow(),
                message="Already enrolled in course"
            )
        )
    
    # Create enrollment
    progress = UserCourseProgress(
        user_id=current_user.id,
        course_id=course_id,
        progress_percentage=0.0
    )
    db.add(progress)
    await db.commit()
    await db.refresh(progress)
    
    return ApiResponse(
        data=EnrollmentResponse(
            course_id=course_id,
            user_id=current_user.id,
            enrolled_at=progress.started_at,
            message="Successfully enrolled in course"
        )
    )
