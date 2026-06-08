import asyncio
import sys
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append("/app")

from app.models.vocabulary import VocabularyItem
from app.core.config import settings

async def main():
    print("Database URL:", settings.async_database_url)
    engine = create_async_engine(settings.async_database_url, echo=False)
    AsyncSessionLocal = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with AsyncSessionLocal() as session:
        result = await session.execute(select(VocabularyItem))
        items = result.scalars().all()
        cnt = 0
        for item in items:
            if item.tags and "basic_200" in item.tags:
                cnt += 1
        print("Python count basic_200:", cnt)

if __name__ == "__main__":
    asyncio.run(main())
