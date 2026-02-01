"""
Migration Script: Add Course Categories

This script creates the course_categories table and adds category_id to courses table.
It also seeds some initial categories.

Run this script after stopping the backend service:
    python -m backend-service.scripts.add_course_categories
"""

import asyncio
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import text
from app.core.database import get_async_engine, get_async_session_maker
from app.models.course_category import CourseCategory
import uuid


async def create_course_categories_table():
    """Create course_categories table."""
    engine = get_async_engine()
    
    create_table_sql = """
    CREATE TABLE IF NOT EXISTS course_categories (
        id UUID PRIMARY KEY,
        name VARCHAR(100) NOT NULL UNIQUE,
        slug VARCHAR(100) NOT NULL UNIQUE,
        description TEXT,
        icon VARCHAR(50),
        color VARCHAR(20),
        order_index INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE,
        course_count INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    
    CREATE INDEX IF NOT EXISTS idx_category_slug ON course_categories(slug);
    CREATE INDEX IF NOT EXISTS idx_category_active ON course_categories(is_active);
    CREATE INDEX IF NOT EXISTS idx_category_active_order ON course_categories(is_active, order_index);
    """
    
    async with engine.begin() as conn:
        await conn.execute(text(create_table_sql))
        print("✓ Created course_categories table")


async def add_category_id_to_courses():
    """Add category_id column to courses table."""
    engine = get_async_engine()
    
    alter_table_sql = """
    -- Add category_id column if it doesn't exist
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name='courses' AND column_name='category_id'
        ) THEN
            ALTER TABLE courses ADD COLUMN category_id UUID;
            ALTER TABLE courses ADD CONSTRAINT fk_course_category 
                FOREIGN KEY (category_id) REFERENCES course_categories(id) ON DELETE SET NULL;
            CREATE INDEX IF NOT EXISTS idx_course_category ON courses(category_id);
        END IF;
    END $$;
    """
    
    async with engine.begin() as conn:
        await conn.execute(text(alter_table_sql))
        print("✓ Added category_id column to courses table")


async def seed_initial_categories():
    """Seed initial course categories."""
    SessionLocal = get_async_session_maker()
    
    categories = [
        {
            "id": str(uuid.uuid4()),
            "name": "Grammar",
            "slug": "grammar",
            "description": "Master English grammar rules and structures",
            "icon": "📚",
            "color": "#4CAF50",
            "order_index": 1
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Vocabulary",
            "slug": "vocabulary",
            "description": "Expand your English vocabulary",
            "icon": "📖",
            "color": "#2196F3",
            "order_index": 2
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Business English",
            "slug": "business-english",
            "description": "Professional English for the workplace",
            "icon": "💼",
            "color": "#FF9800",
            "order_index": 3
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Conversation",
            "slug": "conversation",
            "description": "Practice everyday English conversations",
            "icon": "💬",
            "color": "#9C27B0",
            "order_index": 4
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Travel English",
            "slug": "travel-english",
            "description": "Essential English for travelers",
            "icon": "✈️",
            "color": "#00BCD4",
            "order_index": 5
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Pronunciation",
            "slug": "pronunciation",
            "description": "Improve your English pronunciation",
            "icon": "🗣️",
            "color": "#F44336",
            "order_index": 6
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Test Preparation",
            "slug": "test-preparation",
            "description": "Prepare for IELTS, TOEFL, and other exams",
            "icon": "📝",
            "color": "#673AB7",
            "order_index": 7
        },
        {
            "id": str(uuid.uuid4()),
            "name": "Cultural English",
            "slug": "cultural-english",
            "description": "Learn about English-speaking cultures",
            "icon": "🌍",
            "color": "#8BC34A",
            "order_index": 8
        }
    ]
    
    async with SessionLocal() as session:
        for cat_data in categories:
            # Check if category already exists
            result = await session.execute(
                text("SELECT id FROM course_categories WHERE slug = :slug"),
                {"slug": cat_data["slug"]}
            )
            if result.first():
                print(f"  - Category '{cat_data['name']}' already exists, skipping")
                continue
            
            # Insert category
            await session.execute(
                text("""
                    INSERT INTO course_categories 
                    (id, name, slug, description, icon, color, order_index, is_active, course_count)
                    VALUES (:id, :name, :slug, :description, :icon, :color, :order_index, TRUE, 0)
                """),
                cat_data
            )
            print(f"  + Added category: {cat_data['name']}")
        
        await session.commit()
    
    print("✓ Seeded initial categories")


async def main():
    """Run all migration steps."""
    print("=== Course Categories Migration ===\n")
    
    try:
        print("Step 1: Creating course_categories table...")
        await create_course_categories_table()
        
        print("\nStep 2: Adding category_id to courses table...")
        await add_category_id_to_courses()
        
        print("\nStep 3: Seeding initial categories...")
        await seed_initial_categories()
        
        print("\n✅ Migration completed successfully!")
        print("\nNext steps:")
        print("1. Assign categories to existing courses via admin panel or API")
        print("2. Run: POST /api/v1/categories/update-counts to update course counts")
        
    except Exception as e:
        print(f"\n❌ Migration failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
