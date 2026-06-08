"""Verify starter catalog quality and per-user seeding."""

import asyncio
import sys
import uuid

from sqlalchemy import delete, func, select

sys.path.append("/app")

from app.core.database import AsyncSessionLocal
from app.crud.vocabulary import vocabulary_crud
from app.models.user import User
from app.models.vocabulary import UserVocabulary, VocabularyItem
from app.services.vocabulary_catalog_policy import (
    STARTER_TOPIC_QUOTAS,
    VocabularyCandidate,
    has_tag,
    select_balanced_starter_vocabulary,
)


async def main() -> None:
    async with AsyncSessionLocal() as session:
        catalog = list((await session.execute(select(VocabularyItem))).scalars().all())
        basic_items = [item for item in catalog if has_tag(item.tags, "basic_200")]
        assignments = select_balanced_starter_vocabulary(
            VocabularyCandidate(
                id=item.id,
                word=item.word,
                definition=item.definition,
                usage_frequency=item.usage_frequency,
                tags=item.tags,
                created_at=item.created_at,
            )
            for item in basic_items
        )
        counts = {
            topic: sum(assignment.topic == topic for assignment in assignments)
            for topic in STARTER_TOPIC_QUOTAS
        }
        assert len(assignments) == 200
        assert counts == STARTER_TOPIC_QUOTAS
        print(f"Starter catalog verified: {counts}")

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

        try:
            await vocabulary_crud.ensure_basic_words_for_user(
                session,
                test_user_id,
            )
            after_count = await session.scalar(
                select(func.count(UserVocabulary.id)).where(
                    UserVocabulary.user_id == test_user_id
                )
            )
            assert after_count == 200, f"Expected 200 words, got {after_count}"
            print("Per-user seeding verified: 200 words.")
        finally:
            await session.execute(
                delete(UserVocabulary).where(UserVocabulary.user_id == test_user_id)
            )
            await session.execute(delete(User).where(User.id == test_user_id))
            await session.commit()


if __name__ == "__main__":
    asyncio.run(main())
