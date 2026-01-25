"""
Progress CRUD Operations
Database operations for tracking user progress
"""
from typing import Optional
from datetime import datetime, timedelta
from sqlalchemy import select, func, and_, desc
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
    async def update_course_progress(
        db: AsyncSession,
        user_id: str,
        course_id: str,
        progress_percentage: float,
        xp_earned: int = 0
    ) -> UserCourseProgress:
        """Update user's course progress"""
        progress = await ProgressCRUD.get_user_progress(db, user_id, course_id)
        
        if not progress:
            # Create new progress record
            progress = UserCourseProgress(
                user_id=user_id,
                course_id=course_id,
                progress_percentage=progress_percentage,
                lessons_completed=1,
                total_xp_earned=xp_earned,
                started_at=datetime.utcnow(),
                last_activity_at=datetime.utcnow()
            )
            db.add(progress)
        else:
            # Update existing progress
            progress.progress_percentage = progress_percentage
            progress.total_xp_earned += xp_earned
            progress.last_activity_at = datetime.utcnow()
        
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
                existing.completed_at = datetime.utcnow()
                
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
                completed_at=datetime.utcnow()
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
        
        # Get units with lessons
        units_result = await db.execute(
            select(Unit)
            .where(Unit.course_id == course_id)
            .order_by(Unit.order_index)
        )
        units = units_result.scalars().all()
        
        units_progress = []
        for unit in units:
            # Get lessons for this unit
            lessons_result = await db.execute(
                select(Lesson)
                .where(Lesson.unit_id == unit.id)
                .order_by(Lesson.order_index)
            )
            lessons = lessons_result.scalars().all()
            
            # Count completed lessons in this unit
            completed_count = 0
            for lesson in lessons:
                completion = await ProgressCRUD.get_lesson_completion(
                    db, user_id, str(lesson.id)
                )
                if completion and completion.is_passed:
                    completed_count += 1
            
            units_progress.append({
                'unit_id': str(unit.id),
                'unit_title': unit.title,
                'total_lessons': len(lessons),
                'completed_lessons': completed_count,
                'progress_percentage': (completed_count / len(lessons) * 100) if lessons else 0
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
        course_id: str
    ) -> float:
        """Calculate course progress percentage based on completed lessons"""
        # Get total lessons in course
        course_result = await db.execute(
            select(Course).where(Course.id == course_id)
        )
        course = course_result.scalar_one_or_none()
        if not course or not course.total_lessons:
            return 0.0
        
        # Count completed lessons
        completed_result = await db.execute(
            select(func.count(LessonCompletion.id))
            .join(Lesson, Lesson.id == LessonCompletion.lesson_id)
            .join(Unit, Unit.id == Lesson.unit_id)
            .where(
                and_(
                    Unit.course_id == course_id,
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.is_passed == True
                )
            )
        )
        completed_count = completed_result.scalar() or 0
        
        return (completed_count / course.total_lessons) * 100
    
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
        user_id: str
    ) -> dict:
        """Get comprehensive user statistics"""
        # Total XP
        total_xp = await ProgressCRUD.get_user_total_xp(db, user_id)
        
        # Courses enrolled
        enrolled_result = await db.execute(
            select(func.count(UserCourseProgress.id))
            .where(UserCourseProgress.user_id == user_id)
        )
        courses_enrolled = enrolled_result.scalar() or 0
        
        # Courses completed (100% progress)
        completed_result = await db.execute(
            select(func.count(UserCourseProgress.id))
            .where(
                and_(
                    UserCourseProgress.user_id == user_id,
                    UserCourseProgress.progress_percentage >= 100
                )
            )
        )
        courses_completed = completed_result.scalar() or 0
        
        # Lessons completed
        lessons_result = await db.execute(
            select(func.count(LessonCompletion.id))
            .where(
                and_(
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.is_passed == True
                )
            )
        )
        lessons_completed = lessons_result.scalar() or 0
        
        return {
            'total_xp': total_xp,
            'courses_enrolled': courses_enrolled,
            'courses_completed': courses_completed,
            'lessons_completed': lessons_completed,
            'current_streak': 0,  # TODO: Implement streak calculation
            'longest_streak': 0,  # TODO: Implement streak calculation
            'achievements_unlocked': 0  # TODO: Implement achievements
        }
