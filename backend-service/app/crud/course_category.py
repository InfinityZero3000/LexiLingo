"""
Course Category CRUD Operations

Database operations for course categories.
"""

from typing import List, Optional, Tuple
from sqlalchemy import select, func
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
    async def published_course_counts(db: AsyncSession) -> dict[uuid.UUID, int]:
        """Published courses per category, read live so the number cannot go stale."""
        result = await db.execute(
            select(Course.category_id, func.count(Course.id))
            .where(Course.is_published.is_(True), Course.category_id.is_not(None))
            .group_by(Course.category_id)
        )
        return {category_id: count for category_id, count in result.all()}

    @staticmethod
    async def get_courses_by_category(
        db: AsyncSession,
        category_id: uuid.UUID,
        skip: int = 0,
        limit: int = 20
    ) -> Tuple[List[Course], int]:
        """Published courses filed under the category, by link or by tag."""
        category = await db.get(CourseCategory, category_id)
        if category is None:
            return [], 0
        result = await db.execute(
            select(Course)
            .where(Course.is_published.is_(True))
            .order_by(Course.created_at.desc())
        )
        # The course list in the app groups by tag, and most courses carry
        # tags but no category_id, so a category_id-only query opened an empty
        # page for a category the list showed five courses under.
        # ponytail: filtered in Python because tags is portable JSON; move to
        # SQL (or backfill category_id) if published courses reach thousands.
        labels = {category.slug, category.name.lower()}
        courses = [
            course
            for course in result.scalars().all()
            if course.category_id == category_id
            or labels.intersection(course.tags or [])
        ]
        return courses[skip : skip + limit], len(courses)
