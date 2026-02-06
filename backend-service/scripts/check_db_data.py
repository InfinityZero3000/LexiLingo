"""
Check database data counts and sample data
Run: python -m scripts.check_db_data
"""

import sys
import os
from pathlib import Path

# Add backend-service to path
backend_path = Path(__file__).parent.parent
sys.path.insert(0, str(backend_path))

import asyncio
from sqlalchemy import text
from app.core.database import engine


async def check_data():
    """Check data counts in key tables."""
    async with engine.begin() as conn:
        print("=" * 60)
        print("DATABASE DATA SUMMARY")
        print("=" * 60)
        
        # Check courses
        result = await conn.execute(text('SELECT COUNT(*) FROM courses'))
        courses_count = result.scalar()
        print(f"Courses: {courses_count}")
        
        # Check units
        result = await conn.execute(text('SELECT COUNT(*) FROM units'))
        units_count = result.scalar()
        print(f"Units: {units_count}")
        
        # Check lessons
        result = await conn.execute(text('SELECT COUNT(*) FROM lessons'))
        lessons_count = result.scalar()
        print(f"Lessons: {lessons_count}")
        
        # Check categories
        result = await conn.execute(text('SELECT COUNT(*) FROM course_categories'))
        cat_count = result.scalar()
        print(f"Categories: {cat_count}")
        
        # Check vocabulary
        result = await conn.execute(text('SELECT COUNT(*) FROM vocabulary_items'))
        vocab_count = result.scalar()
        print(f"Vocabulary Items: {vocab_count}")
        
        # Check users
        result = await conn.execute(text('SELECT COUNT(*) FROM users'))
        user_count = result.scalar()
        print(f"Users: {user_count}")
        
        # Check achievements
        result = await conn.execute(text('SELECT COUNT(*) FROM achievements'))
        ach_count = result.scalar()
        print(f"Achievements: {ach_count}")
        
        print("=" * 60)
        
        # Show sample courses if any
        if courses_count > 0:
            result = await conn.execute(text('''
                SELECT title, level, is_published, total_lessons, total_xp 
                FROM courses 
                ORDER BY created_at 
                LIMIT 10
            '''))
            print("\nSAMPLE COURSES:")
            print("-" * 60)
            for row in result.fetchall():
                status = "Published" if row[2] else "Draft"
                print(f"  - {row[0]}")
                print(f"    Level: {row[1]} | Lessons: {row[3]} | XP: {row[4]} | {status}")
        else:
            print("\nNo courses found in database!")
        
        # Show sample categories if any
        if cat_count > 0:
            result = await conn.execute(text('''
                SELECT name, slug, course_count 
                FROM course_categories 
                ORDER BY order_index 
                LIMIT 10
            '''))
            print("\nCATEGORIES:")
            print("-" * 60)
            for row in result.fetchall():
                print(f"  - {row[0]} ({row[1]}) - {row[2]} courses")
        
        print("=" * 60)


if __name__ == "__main__":
    asyncio.run(check_data())
