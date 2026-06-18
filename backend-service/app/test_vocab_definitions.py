import asyncio
import sys
sys.path.insert(0, "/app")
from sqlalchemy import select
from app.core.database import engine
from app.models.vocabulary import VocabularyItem

async def main():
    async with engine.connect() as conn:
        for w in ['idiom', 'lexicon']:
            res = await conn.execute(select(VocabularyItem.word, VocabularyItem.definition, VocabularyItem.part_of_speech).where(VocabularyItem.word == w))
            for row in res.all():
                print(f"Word: {row[0]}, POS: {row[2]}")
                print(f"Def: {row[1]}")
                print("-" * 30)

if __name__ == "__main__":
    asyncio.run(main())
