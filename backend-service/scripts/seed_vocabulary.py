"""
Seed script for vocabulary data
Creates sample vocabulary items for testing Phase 3
"""

import asyncio
import uuid
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.models.vocabulary import VocabularyItem, PartOfSpeech, DifficultyLevel
from app.core.config import settings


# Sample vocabulary data
SAMPLE_VOCABULARY = [
    {
        "word": "hello",
        "definition": "A greeting or an expression of goodwill",
        "translation": {
            "vi": "xin chào",
            "examples": ["Hello, how are you?", "Hello world!", "Say hello to your family"]
        },
        "pronunciation": "/həˈloʊ/",
        "part_of_speech": PartOfSpeech.INTERJECTION,
        "difficulty_level": DifficultyLevel.A1,
        "tags": ["greeting", "common", "daily-conversation"]
    },
    {
        "word": "book",
        "definition": "A written or printed work consisting of pages glued or sewn together along one side and bound in covers",
        "translation": {
            "vi": "cuốn sách",
            "examples": ["I love reading books", "This book is interesting", "Can I borrow your book?"]
        },
        "pronunciation": "/bʊk/",
        "part_of_speech": PartOfSpeech.NOUN,
        "difficulty_level": DifficultyLevel.A1,
        "tags": ["education", "common", "objects"]
    },
    {
        "word": "run",
        "definition": "To move at a speed faster than a walk, never having both or all the feet on the ground at the same time",
        "translation": {
            "vi": "chạy",
            "examples": ["I run every morning", "She runs very fast", "Let's run together"]
        },
        "pronunciation": "/rʌn/",
        "part_of_speech": PartOfSpeech.VERB,
        "difficulty_level": DifficultyLevel.A1,
        "tags": ["sports", "action", "common"]
    },
    {
        "word": "beautiful",
        "definition": "Pleasing the senses or mind aesthetically",
        "translation": {
            "vi": "đẹp",
            "examples": ["What a beautiful day!", "She is beautiful", "The view is beautiful"]
        },
        "pronunciation": "/ˈbjuːtɪfl/",
        "part_of_speech": PartOfSpeech.ADJECTIVE,
        "difficulty_level": DifficultyLevel.A1,
        "tags": ["description", "common", "appearance"]
    },
    {
        "word": "quickly",
        "definition": "At a fast speed; rapidly",
        "translation": {
            "vi": "nhanh chóng",
            "examples": ["Please come quickly", "Time passes quickly", "He walked quickly"]
        },
        "pronunciation": "/ˈkwɪkli/",
        "part_of_speech": PartOfSpeech.ADVERB,
        "difficulty_level": DifficultyLevel.A2,
        "tags": ["manner", "speed", "common"]
    },
    {
        "word": "accomplish",
        "definition": "To achieve or complete successfully",
        "translation": {
            "vi": "hoàn thành, đạt được",
            "examples": ["She accomplished her goal", "We need to accomplish this task", "What did you accomplish today?"]
        },
        "pronunciation": "/əˈkɑːmplɪʃ/",
        "part_of_speech": PartOfSpeech.VERB,
        "difficulty_level": DifficultyLevel.B1,
        "tags": ["achievement", "goal", "formal"]
    },
    {
        "word": "meticulous",
        "definition": "Showing great attention to detail; very careful and precise",
        "translation": {
            "vi": "tỉ mỉ, cẩn thận",
            "examples": ["He is meticulous in his work", "A meticulous planner", "She did a meticulous job"]
        },
        "pronunciation": "/məˈtɪkjələs/",
        "part_of_speech": PartOfSpeech.ADJECTIVE,
        "difficulty_level": DifficultyLevel.B2,
        "tags": ["personality", "work", "precision"]
    },
    {
        "word": "ubiquitous",
        "definition": "Present, appearing, or found everywhere",
        "translation": {
            "vi": "phổ biến ở mọi nơi",
            "examples": ["Smartphones are ubiquitous today", "Coffee shops are ubiquitous in this city", "Social media has become ubiquitous"]
        },
        "pronunciation": "/juːˈbɪkwɪtəs/",
        "part_of_speech": PartOfSpeech.ADJECTIVE,
        "difficulty_level": DifficultyLevel.C1,
        "tags": ["advanced", "academic", "description"]
    },
    {
        "word": "serendipity",
        "definition": "The occurrence of events by chance in a happy or beneficial way",
        "translation": {
            "vi": "sự may mắn bất ngờ, tình cờ may mắn",
            "examples": ["It was pure serendipity that we met", "A moment of serendipity", "Finding this place was serendipity"]
        },
        "pronunciation": "/ˌserənˈdɪpəti/",
        "part_of_speech": PartOfSpeech.NOUN,
        "difficulty_level": DifficultyLevel.C2,
        "tags": ["advanced", "luck", "fate"]
    },
    {
        "word": "ephemeral",
        "definition": "Lasting for a very short time",
        "translation": {
            "vi": "phù du, ngắn ngủi",
            "examples": ["Life is ephemeral", "An ephemeral moment", "The beauty was ephemeral"]
        },
        "pronunciation": "/ɪˈfemərəl/",
        "part_of_speech": PartOfSpeech.ADJECTIVE,
        "difficulty_level": DifficultyLevel.C2,
        "tags": ["advanced", "time", "philosophical"]
    },
]


async def seed_vocabulary():
    """Seed vocabulary items into database"""
    
    # Create async engine
    engine = create_async_engine(
        settings.DATABASE_URL,
        echo=True
    )
    
    # Create async session
    async_session = sessionmaker(
        engine,
        class_=AsyncSession,
        expire_on_commit=False
    )
    
    async with async_session() as session:
        print("🌱 Seeding vocabulary data...")
        
        for vocab_data in SAMPLE_VOCABULARY:
            # Check if word already exists
            from sqlalchemy import select
            result = await session.execute(
                select(VocabularyItem).where(VocabularyItem.word == vocab_data["word"])
            )
            existing = result.scalar_one_or_none()
            
            if existing:
                print(f"⏭️  Skipping '{vocab_data['word']}' (already exists)")
                continue
            
            # Create new vocabulary item
            vocab_item = VocabularyItem(
                id=uuid.uuid4(),
                word=vocab_data["word"],
                definition=vocab_data["definition"],
                translation=vocab_data["translation"],
                pronunciation=vocab_data["pronunciation"],
                part_of_speech=vocab_data["part_of_speech"],
                difficulty_level=vocab_data["difficulty_level"],
                tags=vocab_data["tags"],
                usage_frequency=0
            )
            
            session.add(vocab_item)
            print(f"✅ Added '{vocab_data['word']}' ({vocab_data['difficulty_level']})")
        
        await session.commit()
        print("\n🎉 Vocabulary seeding complete!")
        print(f"Total vocabulary items: {len(SAMPLE_VOCABULARY)}")
    
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(seed_vocabulary())
