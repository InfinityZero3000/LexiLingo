import asyncio
import sys

from app.core.database import engine, Base
from app.models import user, course, progress, vocabulary
import sqlalchemy as sa

async def create_tables():
    try:
        # Use begin() which auto-commits on success
        async with engine.begin() as conn:
            print("Creating tables...")
            await conn.run_sync(Base.metadata.create_all)
        print("✅ All tables created and committed!")
        
        # Verify outside transaction
        async with engine.connect() as conn:
            result = await conn.execute(
                sa.text("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name")
            )
            tables = [row[0] for row in result]
            print(f"\n📋 Created {len(tables)} tables:")
            for table in tables:
                print(f"   - {table}")
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    asyncio.run(create_tables())
