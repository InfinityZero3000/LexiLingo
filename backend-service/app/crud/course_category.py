"""
Course Category CRUD Operations

Database operations for course categories.
"""

from typing import List, Optional, Tuple
from sqlalchemy import select, func, update
from sqlalchemy.ext.asyncio import AsyncSession
import uuid

from app.models.course_category import CourseCategory
from app.models.course import Course


class CourseCategoryCRUD:
    """CRUD operations for CourseCategory."""
    
    @staticmethod
    async def create_category(
        db: AsyncSession,
        name: str,
        slug: str,
        description: Optional[str] = None,
        icon: Optional[str] = None,
        color: Optional[str] = None,
        order_index: int = 0,
        is_active: bool = True
    ) -> CourseCategory:
        """Create a new course category."""
        category = CourseCategory(
            name=name,
            slug=slug,
            description=description,
            icon=icon,
            color=color,
            order_index=order_index,
            is_active=is_active
        )
        db.add(category)
        await db.commit()
        await db.refresh(category)
        return category
    
    @staticmethod
    async def get_category_by_id(
        db: AsyncSession,
        category_id: uuid.UUID
    ) -> Optional[CourseCategory]:
        """Get category by ID."""
        result = await db.execute(
            select(CourseCategory).where(CourseCategory.id == category_id)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_category_by_slug(
        db: AsyncSession,
        slug: str
    ) -> Optional[CourseCategory]:
        """Get category by slug."""
        result = await db.execute(
            select(CourseCategory).where(CourseCategory.slug == slug)
        )
        return result.scalar_one_or_none()
    
    @staticmethod
    async def get_all_categories(
        db: AsyncSession,
        active_only: bool = True,
        skip: int = 0,
        limit: int = 100
    ) -> Tuple[List[CourseCategory], int]:
        """
        Get all categories with pagination.
        Returns (categories, total_count).
        """
        query = select(CourseCategory)
        
        if active_only:
            query = query.where(CourseCategory.is_active == True)
        
        query = query.order_by(CourseCategory.order_index, CourseCategory.name)
        
        # Get total count
        count_query = select(func.count()).select_from(CourseCategory)
        if active_only:
            count_query = count_query.where(CourseCategory.is_active == True)
        
        total_result = await db.execute(count_query)
        total = total_result.scalar()
        
        # Get paginated results
        query = query.offset(skip).limit(limit)
        result = await db.execute(query)
        categories = result.scalars().all()
        
        return list(categories), total
    
    @staticmethod
    async def update_category(
        db: AsyncSession,
        category_id: uuid.UUID,
        **update_data
    ) -> Optional[CourseCategory]:
        """Update category fields."""
        category = await CourseCategoryCRUD.get_category_by_id(db, category_id)
        if not category:
            return None
        
        for field, value in update_data.items():
            if value is not None and hasattr(category, field):
                setattr(category, field, value)
        
        await db.commit()
        await db.refresh(category)
        return category
    
    @staticmethod
    async def delete_category(
        db: AsyncSession,
        category_id: uuid.UUID
    ) -> bool:
        """Delete a category (soft delete by setting is_active to False)."""
        category = await CourseCategoryCRUD.get_category_by_id(db, category_id)
        if not category:
            return False
        
        category.is_active = False
        await db.commit()
        return True
    
    @staticmethod
    async def update_course_counts(db: AsyncSession) -> None:
        """
        Update course_count for all categories.
        Should be called periodically or after course changes.
        """
        # Get counts grouped by category
        query = select(
            Course.category_id,
            func.count(Course.id).label('count')
        ).where(
            Course.is_published == True
        ).group_by(Course.category_id)
        
        result = await db.execute(query)
        counts = {row.category_id: row.count for row in result}
        
        # Update all categories
        for category_id, count in counts.items():
            if category_id:
                await db.execute(
                    update(CourseCategory)
                    .where(CourseCategory.id == category_id)
                    .values(course_count=count)
                )
        
        # Set 0 for categories not in counts
        await db.execute(
            update(CourseCategory)
            .where(CourseCategory.id.notin_(counts.keys()))
            .values(course_count=0)
        )
        
        await db.commit()
    
    @staticmethod
    async def get_courses_by_category(
        db: AsyncSession,
        category_id: uuid.UUID,
        skip: int = 0,
        limit: int = 20
    ) -> Tuple[List[Course], int]:
        """
        Get all courses in a specific category.
        Returns (courses, total_count).
        """
        query = select(Course).where(
            Course.category_id == category_id,
            Course.is_published == True
        ).order_by(Course.created_at.desc())
        
        # Get total count
        count_query = select(func.count()).select_from(Course).where(
            Course.category_id == category_id,
            Course.is_published == True
        )
        total_result = await db.execute(count_query)
        total = total_result.scalar()
        
        # Get paginated results
        query = query.offset(skip).limit(limit)
        result = await db.execute(query)
        courses = result.scalars().all()
        
        return list(courses), total
