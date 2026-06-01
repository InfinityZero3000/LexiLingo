import json
import asyncio
import sys
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append("/app")
from app.models.vocabulary import VocabularyItem, PartOfSpeech
from app.core.config import settings

INPUT_FILE = "/tmp/vocabulary_import.json"

def guess_pos(word, defn):
    if " v." in defn or " verb" in defn or word.startswith("to "):
        return PartOfSpeech.VERB
    if " adj." in defn or " adj " in defn:
        return PartOfSpeech.ADJECTIVE
    if " adv." in defn or " adv " in defn:
        return PartOfSpeech.ADVERB
    if " phrase" in defn or " idiom" in defn or " " in word:
        return PartOfSpeech.PHRASE
    return PartOfSpeech.NOUN

async def main():
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    engine = create_async_engine(settings.async_database_url, echo=False)
    AsyncSessionLocal = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )
    
    async with AsyncSessionLocal() as session:
        # Get all existing word + part_of_speech pairs
        result = await session.execute(select(VocabularyItem.word, VocabularyItem.part_of_speech))
        existing = {(r[0], r[1]) for r in result.all()}
        
        missing_count = 0
        for item in data:
            word = item['word'][:255]
            defn = item.get('definition', '')
            pos = guess_pos(word, defn)
            if (word, pos) not in existing:
                missing_count += 1
                
        print(f"TOTAL_IN_JSON: {len(data)}")
        print(f"EXISTING_IN_DB: {len(existing)}")
        print(f"MISSING_FROM_DB: {missing_count}")

if __name__ == "__main__":
    asyncio.run(main())
