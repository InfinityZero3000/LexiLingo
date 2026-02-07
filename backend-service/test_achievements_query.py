"""Quick test to verify Achievement query works"""
import asyncio
from sqlalchemy import select
from app.core.database import AsyncSessionLocal
from app.models.gamification import Achievement

async def test_query():
    async with AsyncSessionLocal() as db:
        result = await db.execute(
            select(Achievement).order_by(Achievement.category, Achievement.name).limit(3)
        )
        achievements = result.scalars().all()
        print(f"Found {len(achievements)} achievements")
        for a in achievements:
            print(f"  - {a.name} ({a.category}): {a.badge_icon}")

if __name__ == "__main__":
    asyncio.run(test_query())
