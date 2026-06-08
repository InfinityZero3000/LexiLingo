import json
import asyncio
import sys
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append("/app")

from app.models.vocabulary import VocabularyItem
from app.core.config import settings

async def main():
    try:
        with open("/app/vocabulary_import.json", "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        print("Error: /app/vocabulary_import.json not found in the container.")
        return
    except Exception as e:
        print(f"Error reading JSON: {e}")
        return

    words_in_json = [item["word"] for item in data]
    print(f"Total words in JSON file: {len(words_in_json)}")

    engine = create_async_engine(settings.async_database_url, echo=False)
    AsyncSessionLocal = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with AsyncSessionLocal() as session:
        # Check total vocabulary_items count
        total_items = await session.scalar(select(func.count(VocabularyItem.id)))
        print(f"Total vocabulary items in DB: {total_items}")

        # Check sample words from JSON
        sample_words = words_in_json[:10]
        print(f"Checking sample words from JSON: {sample_words}")
        result = await session.execute(
            select(VocabularyItem.word).where(VocabularyItem.word.in_(sample_words))
        )
        found_samples = [r[0] for r in result.all()]
        print(f"Found sample words in DB: {found_samples}")

        # Check how many total words from the JSON are in DB
        # We can query in batches of 1000 to avoid SQL limit issues
        found_count = 0
        batch_size = 1000
        for i in range(0, len(words_in_json), batch_size):
            batch = words_in_json[i:i+batch_size]
            res = await session.execute(
                select(VocabularyItem.word).where(VocabularyItem.word.in_(batch))
            )
            found_count += len(res.all())
        
        print(f"Number of JSON words found in DB: {found_count}")
        print(f"Missing words: {len(words_in_json) - found_count}")

if __name__ == "__main__":
    asyncio.run(main())
