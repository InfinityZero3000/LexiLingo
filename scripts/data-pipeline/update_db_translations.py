import json
import asyncio
import io
import sys
import logging

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import update, text

# Add the app directory to the system path to allow importing app modules
sys.path.append("/app")
from app.models.vocabulary import VocabularyItem
from app.core.config import settings

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

INPUT_FILE = "/app/categorized_words_final.json"

async def update_translations():
    engine = create_async_engine(settings.SQLALCHEMY_DATABASE_URI, echo=False)
    AsyncSessionLocal = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )
    
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        words = json.load(f)
        
    logger.info(f"Loaded {len(words)} words. Updating DB...")
    
    async with AsyncSessionLocal() as db:
        count = 0
        for w in words:
            if "translation" in w:
                stmt = (
                    update(VocabularyItem)
                    .where(VocabularyItem.word == w["word"])
                    .values(translation=w["translation"])
                )
                await db.execute(stmt)
                count += 1
                
                if count % 100 == 0:
                    await db.commit()
                    logger.info(f"Updated {count} records...")
                    
        await db.commit()
        logger.info(f"Finished updating {count} translations in the database.")

if __name__ == "__main__":
    asyncio.run(update_translations())
