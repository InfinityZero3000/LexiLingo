from types import SimpleNamespace

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
