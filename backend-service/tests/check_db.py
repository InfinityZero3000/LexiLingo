"""Quick script to check database connectivity and user existence."""
import asyncio
import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy import text


async def check():
    from app.core.config import settings
    print(f"Main DB URL: {settings.DATABASE_URL}")

    # Check main DB
    try:
        engine = create_async_engine(settings.DATABASE_URL, echo=False)
        async with engine.connect() as conn:
            result = await conn.execute(
                text("SELECT email, level, total_xp FROM users WHERE email = 'nhthang312@gmail.com'")
            )
            row = result.fetchone()
            if row:
                print(f"Found user: email={row[0]}, level={row[1]}, xp={row[2]}")
            else:
                print("User nhthang312@gmail.com NOT FOUND in main DB")
        await engine.dispose()
    except Exception as e:
        print(f"Main DB error: {e}")

    # Check test DB
    test_url = "postgresql+asyncpg://lexilingo:lexilingo_pass@localhost:5432/lexilingo_test"
    try:
        engine2 = create_async_engine(test_url, echo=False)
        async with engine2.connect() as conn:
            await conn.execute(text("SELECT 1"))
        print("Test DB (lexilingo_test): OK")
        await engine2.dispose()
    except Exception as e:
        print(f"Test DB error: {e}")


if __name__ == "__main__":
    asyncio.run(check())
