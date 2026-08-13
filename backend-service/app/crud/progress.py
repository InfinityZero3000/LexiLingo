"""
Progress CRUD Operations
Database operations for tracking user progress
"""
from typing import Optional, List
from datetime import datetime, timedelta, timezone
from sqlalchemy import select, func, and_, desc, case
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.progress import UserCourseProgress, LessonCompletion
from app.models.course import Course, Unit, Lesson


class ProgressCRUD:
    """CRUD operations for user progress tracking"""
    
    @staticmethod
    async def get_user_progress(
        db: AsyncSession,
        user_id: str,
        course_id: str
    ) -> Optional[UserCourseProgress]:
        """Get user's progress for a specific course"""
        result = await db.execute(
            select(UserCourseProgress).where(
                and_(
                    UserCourseProgress.user_id == user_id,
                    UserCourseProgress.course_id == course_id
                )
            )
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_all_user_progress(
        db: AsyncSession,
        user_id: str
    ) -> list[UserCourseProgress]:
        """Get all course progress for a user"""
        result = await db.execute(
            select(UserCourseProgress)
            .where(UserCourseProgress.user_id == user_id)
            .order_by(desc(UserCourseProgress.last_activity_at))
        )
        return result.scalars().all()

    @staticmethod
    async def get_user_progress_with_courses(
        db: AsyncSession,
        user_id: str,
        limit: int = 10,
    ) -> List[tuple[UserCourseProgress, Course]]:
        """Get user progress joined with course data in a single query."""
        result = await db.execute(
            select(UserCourseProgress, Course)
            .join(Course, Course.id == UserCourseProgress.course_id)
            .where(UserCourseProgress.user_id == user_id)
            .order_by(desc(UserCourseProgress.last_activity_at))
            .limit(limit)
        )
        return result.all()

    @staticmethod
    async def update_course_progress(
        db: AsyncSession,
        user_id: str,
        course_id: str,
        progress_percentage: float,
        xp_earned: int = 0
    ) -> UserCourseProgress:
        """Update user's course progress"""
        # Count actual passed lessons for this course from lesson_completions
        count_result = await db.execute(
            select(func.count(LessonCompletion.id))
            .join(Lesson, Lesson.id == LessonCompletion.lesson_id)
            .join(Unit, Unit.id == Lesson.unit_id)
            .where(
                and_(
                    Unit.course_id == course_id,
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.is_passed == True,
                )
            )
        )
        actual_lessons_completed = count_result.scalar() or 0

        progress = await ProgressCRUD.get_user_progress(db, user_id, course_id)

        if not progress:
            progress = UserCourseProgress(
                user_id=user_id,
                course_id=course_id,
                progress_percentage=progress_percentage,
                lessons_completed=actual_lessons_completed,
                total_xp_earned=xp_earned,
                started_at=datetime.now(timezone.utc),
                last_activity_at=datetime.now(timezone.utc)
            )
            db.add(progress)
        else:
            progress.progress_percentage = progress_percentage
            progress.lessons_completed = actual_lessons_completed
            progress.total_xp_earned += xp_earned
            progress.last_activity_at = datetime.now(timezone.utc)

        await db.commit()
        await db.refresh(progress)
        return progress
    
    @staticmethod
    async def get_lesson_completion(
        db: AsyncSession,
        user_id: str,
        lesson_id: str
    ) -> Optional[LessonCompletion]:
        """Get lesson completion record"""
        result = await db.execute(
            select(LessonCompletion).where(
                and_(
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.lesson_id == lesson_id
                )
            )
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def mark_lesson_complete(
        db: AsyncSession,
        user_id: str,
        lesson_id: str,
        score: float,
        pass_threshold: float = 80.0
    ) -> tuple[LessonCompletion, int]:
        """
        Mark a lesson as complete and return completion record + XP earned
        Returns: (LessonCompletion, xp_earned)
        """
        # Get lesson details
        lesson_result = await db.execute(
            select(Lesson).where(Lesson.id == lesson_id)
        )
        lesson = lesson_result.scalar_one_or_none()
        
        if not lesson:
            raise ValueError(f"Lesson {lesson_id} not found")
        
        is_passed = score >= pass_threshold
        
        # Check existing completion
        existing = await ProgressCRUD.get_lesson_completion(db, user_id, lesson_id)
        
        xp_earned = 0
        if existing:
            # Update if new score is better
            if score > existing.best_score:
                old_passed = existing.is_passed
                existing.best_score = score
                existing.is_passed = is_passed
                existing.completed_at = datetime.now(timezone.utc)
                
                # Award XP only if wasn't passed before but is now
                if is_passed and not old_passed:
                    xp_earned = lesson.xp_reward or 0
                
                await db.commit()
                await db.refresh(existing)
                return existing, xp_earned
            else:
                # No improvement, no XP
                return existing, 0
        else:
            # Create new completion record
            completion = LessonCompletion(
                user_id=user_id,
                lesson_id=lesson_id,
                is_passed=is_passed,
                best_score=score,
                completed_at=datetime.now(timezone.utc)
            )
            db.add(completion)
            
            # Award XP if passed
            if is_passed:
                xp_earned = lesson.xp_reward or 0
            
            await db.commit()
            await db.refresh(completion)
            return completion, xp_earned
    
    @staticmethod
    async def get_course_progress_detail(
        db: AsyncSession,
        user_id: str,
        course_id: str
    ) -> Optional[dict]:
        """Get detailed progress for a course including units"""
        # Get course
        course_result = await db.execute(
            select(Course).where(Course.id == course_id)
        )
        course = course_result.scalar_one_or_none()
        if not course:
            return None
        
        # Get user progress
        progress = await ProgressCRUD.get_user_progress(db, user_id, course_id)
        if not progress:
            return None
        
        # Single JOIN query: lessons + passed completions per unit — no N+1
        rows = await db.execute(
            select(
                Unit.id,
                Unit.title,
                func.count(Lesson.id).label("total_lessons"),
                func.sum(
                    case(
                        (and_(LessonCompletion.user_id == user_id, LessonCompletion.is_passed == True), 1),
                        else_=0,
                    )
                ).label("completed_lessons"),
            )
            .join(Lesson, Lesson.unit_id == Unit.id, isouter=True)
            .join(
                LessonCompletion,
                and_(LessonCompletion.lesson_id == Lesson.id, LessonCompletion.user_id == user_id),
                isouter=True,
            )
            .where(Unit.course_id == course_id)
            .group_by(Unit.id, Unit.title, Unit.order_index)
            .order_by(Unit.order_index)
        )

        units_progress = []
        for row in rows:
            total = row.total_lessons or 0
            completed = int(row.completed_lessons or 0)
            units_progress.append({
                'unit_id': str(row.id),
                'unit_title': row.title,
                'total_lessons': total,
                'completed_lessons': completed,
                'progress_percentage': (completed / total * 100) if total else 0,
            })
        
        return {
            'course': {
                'course_id': str(course.id),
                'course_title': course.title,
                'progress_percentage': progress.progress_percentage,
                'lessons_completed': progress.lessons_completed,
                'total_lessons': course.total_lessons or 0,
                'total_xp_earned': progress.total_xp_earned,
                'started_at': progress.started_at,
                'last_activity_at': progress.last_activity_at,
            },
            'units_progress': units_progress
        }
    
    @staticmethod
    async def calculate_course_progress(
        db: AsyncSession,
        user_id: str,
        course_id: str,
    ) -> float:
        """Calculate course progress percentage based on completed lessons.

        Counts the lessons that actually exist rather than trusting the
        denormalized ``Course.total_lessons`` — otherwise a learner who
        finishes everything can be stuck below 100%.
        """
        total_result = await db.execute(
            select(func.count(Lesson.id))
            .join(Unit, Unit.id == Lesson.unit_id)
            .where(Unit.course_id == course_id)
        )
        total_lessons = total_result.scalar() or 0

        if not total_lessons:
            return 0.0

        completed_result = await db.execute(
            select(func.count(LessonCompletion.id))
            .join(Lesson, Lesson.id == LessonCompletion.lesson_id)
            .join(Unit, Unit.id == Lesson.unit_id)
            .where(
                and_(
                    Unit.course_id == course_id,
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.is_passed == True,
                )
            )
        )
        completed_count = completed_result.scalar() or 0
        return (completed_count / total_lessons) * 100
    
    @staticmethod
    async def get_user_total_xp(
        db: AsyncSession,
        user_id: str
    ) -> int:
        """Get user's total XP across all courses"""
        result = await db.execute(
            select(func.sum(UserCourseProgress.total_xp_earned))
            .where(UserCourseProgress.user_id == user_id)
        )
        return result.scalar() or 0
    
    @staticmethod
    async def get_user_stats(
        db: AsyncSession,
        user_id: str,
    ) -> dict:
        """Get comprehensive user statistics in a single query."""
        # One query: XP + enrolled + completed counts from UserCourseProgress
        progress_result = await db.execute(
            select(
                func.coalesce(func.sum(UserCourseProgress.total_xp_earned), 0).label("total_xp"),
                func.count(UserCourseProgress.id).label("courses_enrolled"),
                func.sum(
                    case((UserCourseProgress.progress_percentage >= 100, 1), else_=0)
                ).label("courses_completed"),
            ).where(UserCourseProgress.user_id == user_id)
        )
        row = progress_result.one()

        # Second query: passed lesson count (separate table)
        lessons_result = await db.execute(
            select(func.count(LessonCompletion.id)).where(
                and_(
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.is_passed == True,
                )
            )
        )
        lessons_completed = lessons_result.scalar() or 0

        return {
            'total_xp': int(row.total_xp or 0),
            'courses_enrolled': int(row.courses_enrolled or 0),
            'courses_completed': int(row.courses_completed or 0),
            'lessons_completed': lessons_completed,
            'current_streak': 0,
            'longest_streak': 0,
            'achievements_unlocked': 0,
        }
