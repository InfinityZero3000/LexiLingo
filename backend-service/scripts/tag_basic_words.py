import json
import asyncio
import sys
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append("/app")

from app.models.vocabulary import VocabularyItem, PartOfSpeech
from app.core.config import settings
from scripts.import_json_to_db import guess_pos

async def main():
    try:
        with open("/app/vocabulary_import.json", "r", encoding="utf-8") as f:
            data = json.load(f)
    except FileNotFoundError:
        print("Error: /app/vocabulary_import.json not found.")
        return

    # Take first 200 items from JSON
    basic_items = data[:200]
    print(f"Loaded {len(basic_items)} basic items from JSON.")

    engine = create_async_engine(settings.async_database_url, echo=False)
    AsyncSessionLocal = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with AsyncSessionLocal() as session:
        tagged_count = 0
        for item in basic_items:
            word = item["word"]
            defn = item.get("definition", "")
            pos = guess_pos(word, defn)
            
            # Find matching item in DB
            result = await session.execute(
                select(VocabularyItem).where(
                    VocabularyItem.word == word,
                    VocabularyItem.part_of_speech == pos
                )
            )
            db_items = result.scalars().all()
            
            if not db_items:
                # Fallback to word only if POS doesn't match
                result = await session.execute(
                    select(VocabularyItem).where(VocabularyItem.word == word)
                )
                db_items = result.scalars().all()
                
            for db_item in db_items:
                tags = db_item.tags or []
                if not isinstance(tags, list):
                    tags = [tags] if tags else []
                if "basic_200" not in tags:
                    new_tags = list(tags) + ["basic_200"]
                    db_item.tags = new_tags
                    session.add(db_item)
                    tagged_count += 1
        
        await session.commit()
        print(f"Tagged {tagged_count} vocabulary items with 'basic_200' tag.")

if __name__ == "__main__":
    asyncio.run(main())
