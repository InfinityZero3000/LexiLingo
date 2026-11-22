"""Quick-save on Postgres: race-free find-or-create, re-save scheduling, enrichment dedup, corpus audit."""

import asyncio
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.main import app
from app.models.learner_state import LearnerConceptState, LearnerObservationEvent
from app.models.vocabulary import (
    UserVocabulary,
    VocabularyItem,
    VocabularyReview,
    VocabularyStatus,
)
from app.services import reference_content

URL = "/api/v1/vocabulary/collection/quick-save"
LOOKUP = {"definition": "a round fruit", "translation": "quả táo", "part_of_speech": "noun"}


@pytest.fixture(autouse=True)
def _no_side_effects():
    with patch("app.routes.vocabulary._lookup_word", new=AsyncMock(return_value=LOOKUP)), \
         patch("app.routes.vocabulary.schedule_enrichment", new=AsyncMock(return_value=False)):
        yield


@pytest.fixture
async def client(db_engine, test_user):
    maker = async_sessionmaker(db_engine, class_=AsyncSession, expire_on_commit=False)

    async def fresh_session():
        async with maker() as session:
            yield session

    async def current_user():
        return test_user

    app.dependency_overrides[get_db] = fresh_session
    app.dependency_overrides[get_current_user] = current_user
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c:
        c.maker = maker
        yield c
    app.dependency_overrides.clear()


async def _save(client, word="apple"):
    response = await client.post(URL, json={"word": word, "source_type": "news"})
    assert response.status_code == 201, response.text
    return response.json()


async def _row(client, user_id, word="apple") -> UserVocabulary:
    async with client.maker() as db:
        return (
            await db.execute(
                select(UserVocabulary)
                .join(VocabularyItem, VocabularyItem.id == UserVocabulary.vocabulary_id)
                .where(UserVocabulary.user_id == user_id, func.lower(VocabularyItem.word) == word)
            )
        ).scalar_one()


async def _set(client, row_id, **values):
    async with client.maker() as db:
        row = await db.get(UserVocabulary, row_id)
        for key, value in values.items():
            setattr(row, key, value)
        await db.commit()


async def _count(client, model) -> int:
    async with client.maker() as db:
        return (await db.execute(select(func.count()).select_from(model))).scalar_one()


@pytest.mark.asyncio
async def test_lower_word_index_exists(db_engine):
    async with db_engine.connect() as conn:
        definition = (
            await conn.execute(
                text("SELECT indexdef FROM pg_indexes WHERE indexname = 'ix_vocabulary_items_lower_word'")
            )
        ).scalar_one()
    assert "lower((word)::text)" in definition


@pytest.mark.asyncio
async def test_concurrent_quick_saves_of_a_new_word_create_one_row(client):
    results = await asyncio.gather(*[_save(client, "Apple") for _ in range(8)])
    assert await _count(client, VocabularyItem) == 1
    assert len({r["vocabulary"]["id"] for r in results}) == 1
    assert sum(1 for r in results if r["created_new_item"]) == 1


@pytest.mark.asyncio
async def test_case_variants_resolve_to_one_item(client):
    first = await _save(client, "Apple")
    second = await _save(client, "apple")
    third = await _save(client, "APPLE")
    assert first["vocabulary"]["id"] == second["vocabulary"]["id"] == third["vocabulary"]["id"]
    assert await _count(client, VocabularyItem) == 1


@pytest.mark.asyncio
async def test_first_save_is_not_a_resave(client, test_user):
    data = await _save(client)
    assert data["already_in_collection"] is False
    assert data["review_scheduled"] is False
    row = await _row(client, test_user.id)
    assert row.resave_count == 0 and row.last_resaved_at is None


@pytest.mark.asyncio
async def test_resave_makes_the_word_due_now(client, test_user):
    await _save(client)
    row = await _row(client, test_user.id)
    before = datetime.now(timezone.utc)
    await _set(client, row.id, next_review_date=before + timedelta(days=9), interval=9, ease_factor=2.1)

    data = await _save(client)

    assert data["already_in_collection"] is True
    assert data["review_scheduled"] is True
    assert data["created_new_item"] is False
    assert datetime.fromisoformat(data["next_review_date"]) <= datetime.now(timezone.utc)
    row = await _row(client, test_user.id)
    assert row.resave_count == 1
    assert row.last_resaved_at is not None
    assert row.next_review_date <= datetime.now(timezone.utc)
    assert (row.interval, row.ease_factor, row.repetitions) == (9, 2.1, 0)


@pytest.mark.asyncio
async def test_second_resave_inside_cooldown_changes_nothing(client, test_user):
    await _save(client)
    row = await _row(client, test_user.id)
    await _set(client, row.id, next_review_date=datetime.now(timezone.utc) + timedelta(days=5))
    assert (await _save(client))["review_scheduled"] is True
    await _set(client, row.id, next_review_date=datetime.now(timezone.utc) + timedelta(days=5))

    again = await _save(client)

    assert again["review_scheduled"] is False
    row = await _row(client, test_user.id)
    assert row.resave_count == 1
    assert row.next_review_date > datetime.now(timezone.utc) + timedelta(days=4)


@pytest.mark.asyncio
async def test_resave_after_the_cooldown_counts_again(client, test_user):
    await _save(client)
    row = await _row(client, test_user.id)
    await _set(
        client, row.id,
        next_review_date=datetime.now(timezone.utc) + timedelta(days=5),
        last_resaved_at=datetime.now(timezone.utc) - timedelta(minutes=11),
        resave_count=1,
    )
    assert (await _save(client))["review_scheduled"] is True
    assert (await _row(client, test_user.id)).resave_count == 2


@pytest.mark.asyncio
async def test_concurrent_resaves_count_once(client, test_user):
    await _save(client)
    row = await _row(client, test_user.id)
    await _set(client, row.id, next_review_date=datetime.now(timezone.utc) + timedelta(days=5))
    results = await asyncio.gather(*[_save(client) for _ in range(5)])
    assert sum(1 for r in results if r["review_scheduled"]) == 1
    assert (await _row(client, test_user.id)).resave_count == 1


@pytest.mark.asyncio
async def test_already_due_word_is_left_alone(client, test_user):
    await _save(client)
    row = await _row(client, test_user.id)
    await _set(client, row.id, next_review_date=datetime.now(timezone.utc) - timedelta(hours=1))
    data = await _save(client)
    assert data["already_in_collection"] is True
    assert data["review_scheduled"] is False
    assert (await _row(client, test_user.id)).resave_count == 0


@pytest.mark.asyncio
@pytest.mark.parametrize("status", [VocabularyStatus.MASTERED, VocabularyStatus.ARCHIVED])
async def test_mastered_or_archived_word_returns_to_reviewing(client, test_user, status):
    await _save(client)
    row = await _row(client, test_user.id)
    await _set(client, row.id, status=status, next_review_date=datetime.now(timezone.utc) + timedelta(days=40))
    data = await _save(client)
    assert data["review_scheduled"] is True
    row = await _row(client, test_user.id)
    assert row.status == VocabularyStatus.REVIEWING
    assert row.next_review_date <= datetime.now(timezone.utc)


@pytest.mark.asyncio
async def test_resave_writes_no_review_or_learner_signal(client, test_user):
    await _save(client)
    row = await _row(client, test_user.id)
    await _set(client, row.id, next_review_date=datetime.now(timezone.utc) + timedelta(days=5))
    await _save(client)
    assert await _count(client, VocabularyReview) == 0
    assert await _count(client, LearnerConceptState) == 0
    assert await _count(client, LearnerObservationEvent) == 0


@pytest.mark.asyncio
async def test_export_audit_counts_duplicates(caplog):
    rows = [
        {"word": "Apple", "part_of_speech": "noun"},
        {"word": "apple", "part_of_speech": "noun"},
        {"word": "apple", "part_of_speech": "verb"},
        {"word": "pear", "part_of_speech": "noun"},
    ]
    assert reference_content.audit_duplicates(rows) == {"by_word_pos": 1, "by_word": 1}
    assert reference_content.audit_duplicates(rows[2:]) == {"by_word_pos": 0, "by_word": 0}

    full = [{**r, "id": str(i), "difficulty_level": "A1"} for i, r in enumerate(rows)]
    with caplog.at_level("WARNING"):
        files = reference_content.build_files({"vocabulary_items": full, "question_bank": []})
    assert '"by_word_pos": 1' in files["vocabulary/manifest.json"]
    assert "duplicate vocabulary rows" in caplog.text

    caplog.clear()
    with caplog.at_level("WARNING"):
        reference_content.build_files({"vocabulary_items": full[3:], "question_bank": []})
    assert "duplicate vocabulary rows" not in caplog.text
