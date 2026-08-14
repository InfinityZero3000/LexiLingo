"""
Direct Course Seeding Script
============================
Seeds achievements, shop items, course categories and sample courses by
calling app.services.admin_seed_service directly.

Run:
    cd backend-service
    venv/bin/python3 scripts/seed_courses_directly.py
"""

import asyncio
import sys
from pathlib import Path

# Add backend directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from app.core.database import AsyncSessionLocal
from app.services import admin_seed_service


async def run_seed():
    async with AsyncSessionLocal() as db:
        print("Running database seeding for courses & exercises...")
        try:
            achievements = await admin_seed_service.seed_achievements(db)
            shop_items = await admin_seed_service.seed_shop_items(db)
            categories, category_ids = await admin_seed_service.seed_course_categories(db)
            courses, units, lessons = await admin_seed_service.seed_courses(
                db, category_ids
            )
            await db.commit()
            print(
                f"Success! {achievements} achievements, {shop_items} shop items, "
                f"{categories} categories, {courses} courses, {units} units, "
                f"{lessons} lessons"
            )
        except Exception as e:
            await db.rollback()
            print("Error during seeding:", e)
            import traceback
            traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(run_seed())
