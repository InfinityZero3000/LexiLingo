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

INPUT_FILE = "/app/data/vocabulary_import.json"

def guess_pos(word, defn):
    # Remove Vietnamese "v.v." / "v. v." to prevent false verb matching on " v."
    clean_defn = defn.replace("v.v.", "").replace("v. v.", "")
    if " v." in clean_defn or " verb" in clean_defn or word.startswith("to "):
        return PartOfSpeech.VERB
    if " adj." in clean_defn or " adj " in clean_defn:
        return PartOfSpeech.ADJECTIVE
    if " adv." in clean_defn or " adv " in clean_defn:
        return PartOfSpeech.ADVERB
    if " phrase" in clean_defn or " idiom" in clean_defn or " " in word:
        return PartOfSpeech.PHRASE
    return PartOfSpeech.NOUN

async def main():
    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    # Database setup
    # PostgreSQL URI from settings or .env
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
                
                # Get the existing translations dictionary from the JSON item if it exists
                trans_dict = item.get('translation', {})
                if not isinstance(trans_dict, dict):
                    trans_dict = {}
                if "vi" not in trans_dict or not trans_dict["vi"]:
                    trans_dict["vi"] = defn

                translation = {
                    **trans_dict,
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
                
                # Get difficulty level from JSON or fall back to A1
                level_str = item.get('difficulty_level', 'A1')
                try:
                    difficulty_level = DifficultyLevel(level_str)
                except ValueError:
                    difficulty_level = DifficultyLevel.A1

                # Parse tags
                tags_raw = item.get('tags', "general")
                if isinstance(tags_raw, str):
                    tags = [t.strip() for t in tags_raw.split(',') if t.strip()]
                else:
                    tags = tags_raw if isinstance(tags_raw, list) else ["general"]

                db_item = dict(
                    id=uuid.uuid4(),
                    word=word,
                    definition=defn,
                    translation=translation,
                    pronunciation=phonetic[:100] if phonetic else None,
                    audio_url=audio_url,
                    part_of_speech=guess_pos(word, defn),
                    difficulty_level=difficulty_level,
                    tags=tags
                )
                items.append(db_item)
            
            from sqlalchemy.dialects.postgresql import insert
            if items:
                stmt = insert(VocabularyItem).values(items)
                # Update existing items with refined definitions, translations, levels, tags, etc.
                stmt = stmt.on_conflict_do_update(
                    index_elements=['word', 'part_of_speech'],
                    set_={
                        'definition': stmt.excluded.definition,
                        'translation': stmt.excluded.translation,
                        'pronunciation': stmt.excluded.pronunciation,
                        'audio_url': stmt.excluded.audio_url,
                        'difficulty_level': stmt.excluded.difficulty_level,
                        'tags': stmt.excluded.tags
                    }
                )
                await session.execute(stmt)
                await session.commit()
            
            total += len(items)
            print(f"Imported {total} / {len(data)}")
            
    print("Done importing strictly formatted Vocabulary items!")

if __name__ == "__main__":
    asyncio.run(main())
