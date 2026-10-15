from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.crud.vocabulary import vocabulary_crud


class _ScalarResult:
    def __init__(self, items):
        self._items = items

    def all(self):
        return self._items


class _ExecuteResult:
    def __init__(self, items):
        self._items = items

    def scalars(self):
        return _ScalarResult(self._items)


class _FakeSession:
    def __init__(self, items):
        self._items = items

    async def execute(self, _query):
        return _ExecuteResult(self._items)


@pytest.mark.asyncio
async def test_topic_filter_supports_aliases_and_rejects_placeholders():
    session = _FakeSession(
        [
            SimpleNamespace(
                word="breakfast",
                definition="The first meal of the day.",
                tags=["daily"],
            ),
            SimpleNamespace(
                word="commute",
                definition="Travel regularly between home and work.",
                tags=["daily_life"],
            ),
            SimpleNamespace(
                word="bad-placeholder",
                definition="#N/A yet",
                tags=["daily"],
            ),
            SimpleNamespace(
                word="clinic",
                definition="A place for medical treatment.",
                tags=["health"],
            ),
        ]
    )

    daily_items = await vocabulary_crud.get_vocabulary_items(
        session,
        tag="daily",
        limit=20,
    )
    health_items = await vocabulary_crud.get_vocabulary_items(
        session,
        tag="health",
        limit=20,
    )

    assert [item.word for item in daily_items] == ["breakfast", "commute"]
    assert [item.word for item in health_items] == ["clinic"]


class _BulkSession:
    def __init__(self, valid_ids, user_vocabulary):
        self.valid_ids = valid_ids
        self.user_vocabulary = user_vocabulary
        self.execute_count = 0
        self.commit_count = 0
        self.statements = []

    async def scalars(self, _query):
        return _ScalarResult(self.valid_ids)

    async def execute(self, _query):
        self.execute_count += 1
        self.statements.append(_query)
        return _ExecuteResult(self.user_vocabulary if self.execute_count == 2 else [])

    async def commit(self):
        self.commit_count += 1


@pytest.mark.asyncio
async def test_bulk_add_uses_one_upsert_fetch_and_commit():
    user_id = uuid4()
    vocabulary_id = uuid4()
    other_vocabulary_id = uuid4()
    missing_id = uuid4()
    user_vocabulary = SimpleNamespace(vocabulary_id=vocabulary_id)
    other_user_vocabulary = SimpleNamespace(vocabulary_id=other_vocabulary_id)
    session = _BulkSession(
        [vocabulary_id, other_vocabulary_id],
        [user_vocabulary, other_user_vocabulary],
    )

    result = await vocabulary_crud.bulk_add_to_collection(
        session,
        user_id=user_id,
        vocabulary_ids=[vocabulary_id, missing_id, vocabulary_id, other_vocabulary_id],
    )

    insert_params = session.statements[0].compile().params.values()
    assert result == [user_vocabulary, user_vocabulary, other_user_vocabulary]
    assert list(insert_params).count(vocabulary_id) == 1
    assert list(insert_params).count(other_vocabulary_id) == 1
    assert missing_id not in insert_params
    assert session.execute_count == 2
    assert session.commit_count == 1
