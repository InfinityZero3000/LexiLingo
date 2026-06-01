import json
import uuid
import sys
import asyncio
from datetime import datetime, timezone

# Add parent directory to Python path
sys.path.append("/app")

from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.models.vocabulary import VocabularyItem, PartOfSpeech, DifficultyLevel
from app.core.config import settings

INPUT_FILE = "/tmp/vocabulary_import.json"

def guess_pos(word, defn):
    # Basic guessing from Anki info
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

    # Database setup
    # PostgreSQL URI from settings or .env
    # Let's read MONGODB_URI/Postgres URI
    engine = create_async_engine(settings.DATABASE_URL, echo=False)
    AsyncSessionLocal = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )
    
    async with AsyncSessionLocal() as session:
        batch_size = 100
        total = 0
        
        for i in range(0, len(data), batch_size):
            batch = data[i:i+batch_size]
            items = []
            
            for item in batch:
                word = item['word'][:255]
                defn = item.get('definition', '')
                example = item.get('example', '')
                phonetic = item.get('phonetic', '')
                
                # Parse additional info
                audios = item.get('audios', {})
                images = item.get('images', '')
                translation = {
                    "vi": defn,
                    "examples": [example] if example else [],
                    "images": images if images else [],
                    "audios": audios if audios else {}
                }

                audio_url = None
                if isinstance(audios, dict):
                    pronunciation = audios.get('pronunciation')
                    if pronunciation:
                        audio_url = f"/media/{pronunciation}"
                elif isinstance(audios, list) and audios:
                    audio_url = f"/media/{audios[0]}"
                
                db_item = dict(
                    id=uuid.uuid4(),
                    word=word,
                    definition=defn,
                    translation=translation,
                    pronunciation=phonetic[:100] if phonetic else None,
                    audio_url=audio_url,
                    part_of_speech=guess_pos(word, defn),
                    difficulty_level=DifficultyLevel.A1, # default placeholder
                    tags=item.get('tags', ["general"])
                )
                items.append(db_item)
            
            from sqlalchemy.dialects.postgresql import insert
            if items:
                stmt = insert(VocabularyItem).values(items)
                # Ignore duplicates based on word + part_of_speech
                stmt = stmt.on_conflict_do_nothing(index_elements=['word', 'part_of_speech'])
                await session.execute(stmt)
                await session.commit()
            
            total += len(items)
            print(f"Imported {total} / {len(data)}")
            
    print("Done importing strictly formatted Vocabulary items!")

if __name__ == "__main__":
    asyncio.run(main())
