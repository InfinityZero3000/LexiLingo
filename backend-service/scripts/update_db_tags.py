import json
import asyncio
import sys
import logging

sys.path.append("/app/app")

from sqlalchemy import update
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from core.database import AsyncSessionLocal, engine
from models.vocabulary import VocabularyItem

INPUT_FILE = "/app/categorized_words_final.json"

async def main():
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)
        
    print(f"Loaded {len(data)} words. Updating DB...")
    
    async with AsyncSessionLocal() as session:
        batch_size = 500
        for i in range(0, len(data), batch_size):
            batch = data[i:i+batch_size]
            for item in batch:
                word = item['word'][:255]
                tags = item.get('tags', ['general'])
                
                # We will perform a simple update
                stmt = update(VocabularyItem).where(VocabularyItem.word == word).values(tags=tags)
                await session.execute(stmt)
            
            await session.commit()
            print(f"Updated {min(i+batch_size, len(data))} / {len(data)}")

if __name__ == "__main__":
    asyncio.run(main())
