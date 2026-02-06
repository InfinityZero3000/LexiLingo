"""Script to check database status for migrations."""
import asyncio
from sqlalchemy import text
from app.core.database import engine


async def check():
    async with engine.begin() as conn:
        # Check tables
        result = await conn.execute(text(
            "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name"
        ))
        tables = [r[0] for r in result.fetchall()]
        print(f'Tables: {len(tables)}')
        for t in tables[:20]:
            print(f'  - {t}')
        if len(tables) > 20:
            print(f'  ... and {len(tables)-20} more')
        
        # Check if users table has level columns
        result = await conn.execute(text(
            "SELECT column_name FROM information_schema.columns WHERE table_name = 'users' AND column_name IN ('numeric_level', 'rank')"
        ))
        cols = [r[0] for r in result.fetchall()]
        print(f'Level columns in users table: {cols}')
        
        # Check alembic_version
        try:
            result = await conn.execute(text("SELECT version_num FROM alembic_version"))
            versions = [r[0] for r in result.fetchall()]
            print(f'Alembic versions: {versions}')
        except Exception as e:
            print(f'Alembic version table error: {e}')


if __name__ == "__main__":
    asyncio.run(check())
