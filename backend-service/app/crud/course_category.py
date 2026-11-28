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
    async def get_category_by_name(
        db: AsyncSession,
        name: str
    ) -> Optional[CourseCategory]:
        """Get category by exact name (the column is unique)."""
        result = await db.execute(
            select(CourseCategory).where(CourseCategory.name == name)
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
    def _extract_tag_set(tags) -> set[str]:
        if not tags:
            return set()
        if isinstance(tags, list):
            return {str(t).strip().lower() for t in tags if t}
        if isinstance(tags, dict):
            out: set[str] = set()
            for v in tags.values():
                if isinstance(v, list):
                    out.update(str(t).strip().lower() for t in v if t)
            return out
        return set()

    @staticmethod
    async def published_course_counts(db: AsyncSession) -> dict[uuid.UUID, int]:
        """Published courses per category (matching by category_id or tag), read live so the number cannot go stale."""
        cat_result = await db.execute(select(CourseCategory))
        categories = list(cat_result.scalars().all())
        if not categories:
            return {}
        course_result = await db.execute(
            select(Course.id, Course.category_id, Course.tags).where(
                Course.is_published.is_(True)
            )
        )
        course_rows = course_result.all()
        counts: dict[uuid.UUID, int] = {}
        for cat in categories:
            labels = {cat.slug.lower(), cat.name.lower()}
            matched = 0
            for _cid, c_cat_id, c_tags in course_rows:
                if c_cat_id == cat.id or labels.intersection(
                    CourseCategoryCRUD._extract_tag_set(c_tags)
                ):
                    matched += 1
            counts[cat.id] = matched
        return counts

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
        labels = {category.slug.lower(), category.name.lower()}
        courses = [
            course
            for course in result.scalars().all()
            if course.category_id == category_id
            or labels.intersection(
                CourseCategoryCRUD._extract_tag_set(course.tags)
            )
        ]
        return courses[skip : skip + limit], len(courses)
