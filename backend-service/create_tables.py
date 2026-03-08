import asyncio
import sys

from app.core.database import engine, Base
from app.models import user, course, progress, vocabulary
from app.models import games  # Phase 3: Games + XP
from app.models import api_cache  # Phase 0: Cache + Quota tables
from app.models import proficiency  # Phase 2: Proficiency system
from app.models import gamification  # Phase 4: Gamification
from app.models import rbac  # Role-based access control
from app.models import content  # Content metadata
from app.models import course_category  # Course categories
from app.models import notification  # Notifications
import sqlalchemy as sa


async def create_tables():
    try:
        # Use begin() which auto-commits on success
        async with engine.begin() as conn:
            print("Creating tables...")
            await conn.run_sync(Base.metadata.create_all)
        print("✅ All tables created and committed!")

        # Verify — works on both PostgreSQL and SQLite
        async with engine.connect() as conn:
            dialect = engine.dialect.name
            if dialect == "sqlite":
                result = await conn.execute(
                    sa.text("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
                )
                tables = [row[0] for row in result]
            else:
                # PostgreSQL / other: use information_schema
                result = await conn.execute(
                    sa.text(
                        "SELECT table_name FROM information_schema.tables "
                        "WHERE table_schema = 'public' ORDER BY table_name"
                    )
                )
                tables = [row[0] for row in result]

            print(f"\n📋 Verified {len(tables)} tables:")
            for table in tables:
                print(f"   - {table}")
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(create_tables())

