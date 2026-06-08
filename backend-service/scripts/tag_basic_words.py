"""Rebuild the balanced basic_200 tags from the current vocabulary catalog."""

import asyncio
import sys

from sqlalchemy import select

sys.path.append("/app")

from app.core.database import AsyncSessionLocal
from app.models.vocabulary import VocabularyItem
from app.services.vocabulary_catalog_policy import (
    VocabularyCandidate,
    normalize_all_tags,
    select_balanced_starter_vocabulary,
)


async def main() -> None:
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(VocabularyItem))
        items = list(result.scalars().all())
        assignments = select_balanced_starter_vocabulary(
            VocabularyCandidate(
                id=item.id,
                word=item.word,
                definition=item.definition,
                usage_frequency=item.usage_frequency,
                tags=item.tags,
                created_at=item.created_at,
            )
            for item in items
        )
        selected_topics = {
            assignment.candidate.id: assignment.topic for assignment in assignments
        }

        for item in items:
            tags = [tag for tag in normalize_all_tags(item.tags) if tag != "basic_200"]
            topic = selected_topics.get(item.id)
            if topic:
                if topic not in tags:
                    tags.append(topic)
                tags.append("basic_200")
            item.tags = tags

        await session.commit()

        counts: dict[str, int] = {}
        for topic in selected_topics.values():
            counts[topic] = counts.get(topic, 0) + 1
        print(f"Tagged {len(assignments)} balanced starter words: {counts}")


if __name__ == "__main__":
    asyncio.run(main())
