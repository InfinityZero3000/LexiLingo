"""
Migration Script: Add total_xp to Users

This script adds the total_xp column to users table and initializes existing users' XP.

Run this script:
    python -m backend-service.scripts.add_user_total_xp
"""

import asyncio
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import text
from app.core.database import get_async_engine


async def add_total_xp_column():
    """Add total_xp column to users table."""
    engine = get_async_engine()
    
    alter_table_sql = """
    -- Add total_xp column if it doesn't exist
    DO $$
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name='users' AND column_name='total_xp'
        ) THEN
            ALTER TABLE users ADD COLUMN total_xp INTEGER DEFAULT 0 NOT NULL;
            RAISE NOTICE 'Added total_xp column to users table';
        ELSE
            RAISE NOTICE 'total_xp column already exists';
        END IF;
    END $$;
    
    -- Update existing users' total_xp from their lesson attempts
    UPDATE users u
    SET total_xp = COALESCE(
        (SELECT SUM(la.xp_earned)
         FROM lesson_attempts la
         WHERE la.user_id = u.id AND la.is_completed = TRUE),
        0
    )
    WHERE u.total_xp = 0;
    
    -- Update users' level based on their total_xp
    UPDATE users
    SET level = CASE
        WHEN total_xp < 1000 THEN 'A1'
        WHEN total_xp < 3000 THEN 'A2'
        WHEN total_xp < 7000 THEN 'B1'
        WHEN total_xp < 15000 THEN 'B2'
        WHEN total_xp < 30000 THEN 'C1'
        ELSE 'C2'
    END
    WHERE level NOT IN ('A1', 'A2', 'B1', 'B2', 'C1', 'C2') OR level = 'beginner';
    """
    
    async with engine.begin() as conn:
        await conn.execute(text(alter_table_sql))
        print("✓ Added total_xp column to users table")
        print("✓ Initialized existing users' XP from lesson attempts")
        print("✓ Updated users' levels based on XP")


async def verify_migration():
    """Verify the migration was successful."""
    engine = get_async_engine()
    
    verify_sql = """
    SELECT 
        COUNT(*) as total_users,
        SUM(total_xp) as total_xp_all_users,
        AVG(total_xp) as avg_xp,
        level,
        COUNT(*) as users_per_level
    FROM users
    GROUP BY level
    ORDER BY 
        CASE level
            WHEN 'A1' THEN 1
            WHEN 'A2' THEN 2
            WHEN 'B1' THEN 3
            WHEN 'B2' THEN 4
            WHEN 'C1' THEN 5
            WHEN 'C2' THEN 6
            ELSE 7
        END;
    """
    
    async with engine.begin() as conn:
        result = await conn.execute(text(verify_sql))
        rows = result.fetchall()
        
        print("\n" + "="*50)
        print("Migration Verification:")
        print("="*50)
        
        if rows:
            print(f"\n{'Level':<10} {'Users':<10}")
            print("-" * 20)
            for row in rows:
                print(f"{row.level:<10} {row.users_per_level:<10}")
        else:
            print("No users found in database")


async def main():
    """Run all migration steps."""
    print("=== Add total_xp to Users Migration ===\n")
    
    try:
        print("Step 1: Adding total_xp column...")
        await add_total_xp_column()
        
        print("\nStep 2: Verifying migration...")
        await verify_migration()
        
        print("\n✅ Migration completed successfully!")
        
    except Exception as e:
        print(f"\n❌ Migration failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
