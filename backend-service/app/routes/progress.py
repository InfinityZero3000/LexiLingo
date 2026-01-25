"""
Progress Routes
API endpoints for tracking user progress
"""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.crud.progress import ProgressCRUD
from app.crud.course import CourseCRUD
from app.schemas.progress import (
    LessonCompletionCreate,
    LessonCompletionResponse,
    UserProgressSummary,
    CourseProgressResponse,
    ProgressStatsResponse
)
from app.schemas.response import ApiResponse
from app.models.user import User

router = APIRouter(prefix="/progress", tags=["Progress"])


@router.get("/me", response_model=ApiResponse[ProgressStatsResponse])
async def get_my_progress(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get current user's overall progress statistics
    
    Returns:
    - Summary: Total XP, courses enrolled/completed, lessons completed
    - Recent activity: Last 7 days of activity
    - Course progress: Progress for all enrolled courses
    """
    # Get user stats
    stats = await ProgressCRUD.get_user_stats(db, str(current_user.id))
    
    # Get all course progress
    all_progress = await ProgressCRUD.get_all_user_progress(db, str(current_user.id))
    
    course_progress_list = []
    for progress in all_progress[:10]:  # Limit to 10 most recent
        course = await CourseCRUD.get_course(db, progress.course_id)
        if course:
            course_progress_list.append({
                'course_id': str(course.id),
                'course_title': course.title,
                'progress_percentage': progress.progress_percentage,
                'lessons_completed': progress.lessons_completed,
                'total_lessons': course.total_lessons or 0,
                'total_xp_earned': progress.total_xp_earned,
                'started_at': progress.started_at,
                'last_activity_at': progress.last_activity_at,
            })
    
    response_data = {
        'summary': stats,
        'recent_activity': [],  # TODO: Implement activity tracking
        'course_progress': course_progress_list
    }
    
    return ApiResponse(
        success=True,
        message="Progress retrieved successfully",
        data=response_data
    )


@router.get("/courses/{course_id}", response_model=ApiResponse[CourseProgressResponse])
async def get_course_progress(
    course_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get detailed progress for a specific course
    
    Returns:
    - Course overview with progress percentage
    - Unit-by-unit progress breakdown
    - Lessons completed per unit
    """
    # Check if course exists
    course = await CourseCRUD.get_course(db, course_id)
    if not course:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Course {course_id} not found"
        )
    
    # Check if user is enrolled
    is_enrolled = await CourseCRUD.is_user_enrolled(db, str(current_user.id), course_id)
    if not is_enrolled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You are not enrolled in this course"
        )
    
    # Get detailed progress
    progress_detail = await ProgressCRUD.get_course_progress_detail(
        db, str(current_user.id), course_id
    )
    
    if not progress_detail:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Progress not found for this course"
        )
    
    return ApiResponse(
        success=True,
        message="Course progress retrieved successfully",
        data=progress_detail
    )


@router.post("/lessons/{lesson_id}/complete", response_model=ApiResponse[LessonCompletionResponse])
async def complete_lesson(
    lesson_id: str,
    completion: LessonCompletionCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Mark a lesson as complete with a score
    
    Requirements:
    - User must be enrolled in the course
    - Score must be between 0-100
    
    Logic:
    - If score >= pass_threshold (80%): Mark as passed, award XP
    - If already completed: Update only if new score is better
    - Updates course progress percentage automatically
    
    Returns:
    - Lesson completion details
    - XP earned (if passed)
    - Updated course progress
    """
    try:
        # Get lesson and verify it exists
        from app.crud.course import LessonCRUD
        lesson = await LessonCRUD.get_lesson(db, lesson_id)
        if not lesson:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Lesson {lesson_id} not found"
            )
        
        # Get unit to find course_id
        from app.crud.course import UnitCRUD
        unit = await UnitCRUD.get_unit(db, str(lesson.unit_id))
        if not unit:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Unit not found for this lesson"
            )
        
        course_id = str(unit.course_id)
        
        # Check if user is enrolled
        is_enrolled = await CourseCRUD.is_user_enrolled(db, str(current_user.id), course_id)
        if not is_enrolled:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You must be enrolled in the course to complete lessons"
            )
        
        # Mark lesson complete
        lesson_completion, xp_earned = await ProgressCRUD.mark_lesson_complete(
            db,
            str(current_user.id),
            lesson_id,
            completion.score,
            lesson.pass_threshold or 80.0
        )
        
        # Recalculate course progress
        new_progress = await ProgressCRUD.calculate_course_progress(
            db, str(current_user.id), course_id
        )
        
        # Update course progress
        course_progress = await ProgressCRUD.update_course_progress(
            db,
            str(current_user.id),
            course_id,
            new_progress,
            xp_earned
        )
        
        # Get user's total XP
        total_xp = await ProgressCRUD.get_user_total_xp(db, str(current_user.id))
        
        message = "Lesson completed successfully"
        if xp_earned > 0:
            message += f" - Earned {xp_earned} XP!"
        elif lesson_completion.is_passed:
            message += " - Already passed, no additional XP"
        else:
            message += f" - Score too low (need {lesson.pass_threshold or 80}% to pass)"
        
        response_data = {
            'lesson_id': lesson_id,
            'is_passed': lesson_completion.is_passed,
            'score': completion.score,
            'best_score': lesson_completion.best_score,
            'xp_earned': xp_earned,
            'total_xp': total_xp,
            'course_progress': new_progress,
            'message': message
        }
        
        return ApiResponse(
            success=True,
            message=message,
            data=response_data
        )
        
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(e)
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error completing lesson: {str(e)}"
        )


@router.get("/xp", response_model=ApiResponse[dict])
async def get_total_xp(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Get user's total XP across all courses
    
    Returns:
    - total_xp: Sum of XP from all courses
    """
    total_xp = await ProgressCRUD.get_user_total_xp(db, str(current_user.id))
    
    return ApiResponse(
        success=True,
        message="Total XP retrieved successfully",
        data={'total_xp': total_xp}
    )
