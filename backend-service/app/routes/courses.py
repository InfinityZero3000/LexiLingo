"""
Course Routes
"""

from typing import List
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.models.course import Course, Lesson
from app.schemas.course import CourseResponse, CourseWithLessons, LessonResponse

router = APIRouter()


@router.get("", response_model=List[CourseResponse])
async def get_courses(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=100),
    language: str = Query(None, description="Filter by language (e.g., 'en')"),
    level: str = Query(None, description="Filter by level (e.g., 'A1')"),
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get list of courses.
    
    Supports filtering by language and level.
    """
    query = select(Course).where(Course.is_published == True)
    
    if language:
        query = query.where(Course.language == language)
    
    if level:
        query = query.where(Course.level == level)
    
    query = query.offset(skip).limit(limit)
    
    result = await db.execute(query)
    courses = result.scalars().all()
    
    return courses


@router.get("/{course_id}", response_model=CourseResponse)
async def get_course(
    course_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get course by ID.
    """
    result = await db.execute(
        select(Course).where(Course.id == course_id)
    )
    course = result.scalar_one_or_none()
    
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found"
        )
    
    return course


@router.get("/{course_id}/lessons", response_model=List[LessonResponse])
async def get_course_lessons(
    course_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get all lessons for a course.
    
    Lessons are returned in order (by order_index).
    """
    # Verify course exists
    result = await db.execute(
        select(Course).where(Course.id == course_id)
    )
    course = result.scalar_one_or_none()
    
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Course not found"
        )
    
    # Get lessons
    result = await db.execute(
        select(Lesson)
        .where(Lesson.course_id == course_id)
        .order_by(Lesson.order_index)
    )
    lessons = result.scalars().all()
    
    return lessons


@router.get("/{course_id}/lessons/{lesson_id}", response_model=LessonResponse)
async def get_lesson(
    course_id: str,
    lesson_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get specific lesson by ID.
    """
    result = await db.execute(
        select(Lesson).where(
            Lesson.id == lesson_id,
            Lesson.course_id == course_id
        )
    )
    lesson = result.scalar_one_or_none()
    
    if not lesson:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Lesson not found"
        )
    
    return lesson
