"""Script to add missing level/rank columns."""
import asyncio
from sqlalchemy import text
from app.core.database import engine


async def add_columns():
    async with engine.begin() as conn:
        # Add numeric_level column if not exists
        await conn.execute(text("""
            ALTER TABLE users 
            ADD COLUMN IF NOT EXISTS numeric_level INTEGER DEFAULT 1 NOT NULL
        """))
        print('Added numeric_level column')
        
        # Add rank column if not exists  
        await conn.execute(text("""
            ALTER TABLE users 
            ADD COLUMN IF NOT EXISTS rank VARCHAR(20) DEFAULT 'bronze' NOT NULL
        """))
        print('Added rank column')
        
        # Verify
        result = await conn.execute(text(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'users' AND column_name IN ('numeric_level', 'rank')"
        ))
        cols = [r[0] for r in result.fetchall()]
        print(f'Verified columns: {cols}')


if __name__ == "__main__":
    asyncio.run(add_columns())
