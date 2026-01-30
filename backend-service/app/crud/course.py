"""
Course CRUD Operations

Database operations for Course, Unit, and Lesson management.
Supports filtering, pagination, and user-specific data (enrollment, progress).
"""

from typing import List, Optional
from sqlalchemy import select, func, and_, or_
from sqlalchemy.orm import Session, selectinload
from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.models.course import Course, Unit, Lesson
from app.models.progress import UserCourseProgress, LessonCompletion
from app.schemas.course import CourseCreate, CourseUpdate, UnitCreate, UnitUpdate, LessonCreate, LessonUpdate


# =====================
# Course CRUD
# =====================

class CourseCRUD:
    """CRUD operations for Course model."""
    
    @staticmethod
    async def get_course(db: AsyncSession, course_id: uuid.UUID) -> Optional[Course]:
        """Get a single course by ID."""
        result = await db.execute(
            select(Course).where(Course.id == course_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_course_with_units(db: AsyncSession, course_id: uuid.UUID) -> Optional[Course]:
        """Get a course with all its units and lessons."""
        result = await db.execute(
            select(Course)
            .options(
                selectinload(Course.units).selectinload(Unit.lessons)
            )
            .where(Course.id == course_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_courses(
        db: AsyncSession,
        skip: int = 0,
        limit: int = 20,
        language: Optional[str] = None,
        level: Optional[str] = None,
        published_only: bool = True
    ) -> tuple[List[Course], int]:
        """
        Get paginated list of courses with optional filters.
        Returns (courses, total_count).
        """
        # Build base query
        query = select(Course)
        count_query = select(func.count(Course.id))
        
        # Apply filters
        filters = []
        if published_only:
            filters.append(Course.is_published == True)
        if language:
            filters.append(Course.language == language)
        if level:
            filters.append(Course.level == level)
        
        if filters:
            query = query.where(and_(*filters))
            count_query = count_query.where(and_(*filters))
        
        # Get total count
        total_result = await db.execute(count_query)
        total = total_result.scalar()
        
        # Get paginated results
        query = query.order_by(Course.created_at.desc()).offset(skip).limit(limit)
        result = await db.execute(query)
        courses = result.scalars().all()
        
        return list(courses), total
    
    @staticmethod
    async def create_course(db: AsyncSession, course: CourseCreate) -> Course:
        """Create a new course."""
        db_course = Course(**course.model_dump())
        db.add(db_course)
        await db.commit()
        await db.refresh(db_course)
        return db_course
    
    @staticmethod
    async def update_course(
        db: AsyncSession,
        course_id: uuid.UUID,
        course_update: CourseUpdate
    ) -> Optional[Course]:
        """Update an existing course."""
        db_course = await CourseCRUD.get_course(db, course_id)
        if not db_course:
            return None
        
        update_data = course_update.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(db_course, field, value)
        
        await db.commit()
        await db.refresh(db_course)
        return db_course
    
    @staticmethod
    async def delete_course(db: AsyncSession, course_id: uuid.UUID) -> bool:
        """Delete a course (soft delete by unpublishing)."""
        db_course = await CourseCRUD.get_course(db, course_id)
        if not db_course:
            return False
        
        db_course.is_published = False
        await db.commit()
        return True
    
    @staticmethod
    async def is_user_enrolled(
        db: AsyncSession,
        user_id: uuid.UUID,
        course_id: uuid.UUID
    ) -> bool:
        """Check if a user is enrolled in a course."""
        result = await db.execute(
            select(UserCourseProgress)
            .where(
                and_(
                    UserCourseProgress.user_id == user_id,
                    UserCourseProgress.course_id == course_id
                )
            )
        )
        return result.scalar_one_or_none() is not None


# =====================
# Unit CRUD
# =====================

class UnitCRUD:
    """CRUD operations for Unit model."""
    
    @staticmethod
    async def get_unit(db: AsyncSession, unit_id: uuid.UUID) -> Optional[Unit]:
        """Get a single unit by ID."""
        result = await db.execute(
            select(Unit).where(Unit.id == unit_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_units_by_course(
        db: AsyncSession,
        course_id: uuid.UUID
    ) -> List[Unit]:
        """Get all units for a course, ordered by order_index."""
        result = await db.execute(
            select(Unit)
            .where(Unit.course_id == course_id)
            .order_by(Unit.order_index)
        )
        return list(result.scalars().all())
    
    @staticmethod
    async def create_unit(db: AsyncSession, unit: UnitCreate) -> Unit:
        """Create a new unit."""
        db_unit = Unit(**unit.model_dump())
        db.add(db_unit)
        await db.commit()
        await db.refresh(db_unit)
        return db_unit
    
    @staticmethod
    async def update_unit(
        db: AsyncSession,
        unit_id: uuid.UUID,
        unit_update: UnitUpdate
    ) -> Optional[Unit]:
        """Update an existing unit."""
        db_unit = await UnitCRUD.get_unit(db, unit_id)
        if not db_unit:
            return None
        
        update_data = unit_update.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(db_unit, field, value)
        
        await db.commit()
        await db.refresh(db_unit)
        return db_unit
    
    @staticmethod
    async def delete_unit(db: AsyncSession, unit_id: uuid.UUID) -> bool:
        """Delete a unit (cascade deletes lessons)."""
        db_unit = await UnitCRUD.get_unit(db, unit_id)
        if not db_unit:
            return False
        
        await db.delete(db_unit)
        await db.commit()
        return True


# =====================
# Lesson CRUD
# =====================

class LessonCRUD:
    """CRUD operations for Lesson model."""
    
    @staticmethod
    async def get_lesson(db: AsyncSession, lesson_id: uuid.UUID) -> Optional[Lesson]:
        """Get a single lesson by ID."""
        result = await db.execute(
            select(Lesson).where(Lesson.id == lesson_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_lessons_by_unit(
        db: AsyncSession,
        unit_id: uuid.UUID
    ) -> List[Lesson]:
        """Get all lessons for a unit, ordered by order_index."""
        result = await db.execute(
            select(Lesson)
            .where(Lesson.unit_id == unit_id)
            .order_by(Lesson.order_index)
        )
        return list(result.scalars().all())
    
    @staticmethod
    async def create_lesson(db: AsyncSession, lesson: LessonCreate) -> Lesson:
        """Create a new lesson."""
        lesson_dict = lesson.model_dump()
        prerequisites = lesson_dict.pop('prerequisites', [])
        
        # Lesson model requires course_id (NOT NULL), but LessonCreate only has unit_id
        # So we need to get the course_id from the unit
        unit_id = lesson_dict.get('unit_id')
        if unit_id:
            from sqlalchemy import select
            from app.models.course import Unit as UnitModel
            result = await db.execute(select(UnitModel).where(UnitModel.id == unit_id))
            unit = result.scalar_one_or_none()
            if unit:
                lesson_dict['course_id'] = unit.course_id
        
        db_lesson = Lesson(**lesson_dict)
        if prerequisites:
            db_lesson.prerequisites = prerequisites
        
        db.add(db_lesson)
        await db.commit()
        await db.refresh(db_lesson)
        return db_lesson
    
    @staticmethod
    async def update_lesson(
        db: AsyncSession,
        lesson_id: uuid.UUID,
        lesson_update: LessonUpdate
    ) -> Optional[Lesson]:
        """Update an existing lesson."""
        db_lesson = await LessonCRUD.get_lesson(db, lesson_id)
        if not db_lesson:
            return None
        
        update_data = lesson_update.model_dump(exclude_unset=True)
        for field, value in update_data.items():
            setattr(db_lesson, field, value)
        
        await db.commit()
        await db.refresh(db_lesson)
        return db_lesson
    
    @staticmethod
    async def delete_lesson(db: AsyncSession, lesson_id: uuid.UUID) -> bool:
        """Delete a lesson."""
        db_lesson = await LessonCRUD.get_lesson(db, lesson_id)
        if not db_lesson:
            return False
        
        await db.delete(db_lesson)
        await db.commit()
        return True
    
    @staticmethod
    async def is_lesson_completed(
        db: AsyncSession,
        user_id: uuid.UUID,
        lesson_id: uuid.UUID
    ) -> bool:
        """Check if a user has completed a lesson."""
        result = await db.execute(
            select(LessonCompletion)
            .where(
                and_(
                    LessonCompletion.user_id == user_id,
                    LessonCompletion.lesson_id == lesson_id,
                    LessonCompletion.is_passed == True
                )
            )
        )
        return result.scalar_one_or_none() is not None
