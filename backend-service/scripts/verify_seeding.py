import asyncio
import sys
import uuid
from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

sys.path.append("/app")

from app.models.vocabulary import UserVocabulary, VocabularyItem
from app.models.user import User
from app.core.config import settings
from app.crud.vocabulary import vocabulary_crud

async def main():
    engine = create_async_engine(settings.async_database_url, echo=False)
    AsyncSessionLocal = sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with AsyncSessionLocal() as session:
        # 1. Create a temporary test user
        test_user_id = uuid.uuid4()
        test_user = User(
            id=test_user_id,
            email=f"test_seed_{test_user_id.hex[:8]}@example.com",
            username=f"test_seed_{test_user_id.hex[:8]}",
            hashed_password="dummy_password",
            display_name="Test Seeding User",
        )
        session.add(test_user)
        await session.commit()
        print(f"Created test user: {test_user.username} (ID: {test_user_id})")

        try:
            # 2. Check initial count in user_vocabulary
            print(f"Database dialect: {session.bind.dialect.name}")
            total_vocab = await session.scalar(select(func.count(VocabularyItem.id)))
            print(f"Total vocabulary items in DB: {total_vocab}")
            
            # Count items tagged with basic_200
            from sqlalchemy.dialects.postgresql import JSONB
            from sqlalchemy import cast
            if session.bind.dialect.name == "postgresql":
                basic_cnt = await session.scalar(
                    select(func.count(VocabularyItem.id)).where(cast(VocabularyItem.tags, JSONB).contains(["basic_200"]))
                )
            else:
                basic_cnt = await session.scalar(
                    select(func.count(VocabularyItem.id)).where(VocabularyItem.tags.contains(["basic_200"]))
                )
            print(f"Total basic_200 tagged items in DB: {basic_cnt}")

            initial_count = await session.scalar(
                select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == test_user_id)
            )
            print(f"Initial user vocabulary count: {initial_count}")

            # 3. Run the automatic seeding logic
            print("Running ensure_basic_words_for_user...")
            await vocabulary_crud.ensure_basic_words_for_user(session, test_user_id)

            # 4. Check user_vocabulary count again
            after_count = await session.scalar(
                select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == test_user_id)
            )
            print(f"User vocabulary count after seeding: {after_count}")

            # Verify that we got exactly 200 words
            assert after_count == 200, f"Expected 200 words, got {after_count}"
            print("Verification successful! Basic 200 words seeded perfectly.")

        finally:
            # Clean up test user and their vocabulary
            await session.execute(delete(UserVocabulary).where(UserVocabulary.user_id == test_user_id))
            await session.execute(delete(User).where(User.id == test_user_id))
            await session.commit()
            print("Cleaned up test data.")

if __name__ == "__main__":
    asyncio.run(main())
