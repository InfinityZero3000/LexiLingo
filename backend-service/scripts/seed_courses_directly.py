"""
Direct Course Seeding Script
============================
Runs the database seeding function from app.routes.admin directly
using the async database session.

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
from app.routes.admin import seed_sample_data

async def run_seed():
    async with AsyncSessionLocal() as db:
        print("Running database seeding for courses & exercises...")
        try:
            # Call seed_sample_data directly (admin_user dependency bypassed)
            response = await seed_sample_data(db=db, admin_user=None)
            print("Success! Seed result message:")
            print("  ", response.message)
        except Exception as e:
            print("Error during seeding:", e)
            import traceback
            traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(run_seed())
