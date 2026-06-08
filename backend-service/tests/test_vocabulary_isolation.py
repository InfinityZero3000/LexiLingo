import pytest
import uuid
from sqlalchemy import select, delete, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import joinedload

from app.models.user import User
from app.models.vocabulary import (
    DifficultyLevel,
    PartOfSpeech,
    UserVocabulary,
    VocabularyDeck,
    VocabularyDeckItem,
    VocabularyItem,
    VocabularyReview,
)
from app.crud.vocabulary import vocabulary_crud


@pytest.fixture
async def basic_vocabulary_catalog(db_session: AsyncSession):
    items = [
        VocabularyItem(
            word=f"basic-ci-{index:03d}",
            definition=f"Basic CI vocabulary item {index}",
            translation={"vi": f"tu-co-ban-{index}"},
            part_of_speech=PartOfSpeech.NOUN,
            difficulty_level=DifficultyLevel.A1,
            tags=["basic_200"],
        )
        for index in range(200)
    ]
    db_session.add_all(items)
    await db_session.commit()
    return items

@pytest.fixture
async def temp_users(db_session: AsyncSession):
    user_a_id = uuid.uuid4()
    user_b_id = uuid.uuid4()
    
    user_a = User(
        id=user_a_id,
        email=f"user_a_{user_a_id.hex[:8]}@example.com",
        username=f"user_a_{user_a_id.hex[:8]}",
        hashed_password="dummy_password",
        display_name="Temp User A",
    )
    user_b = User(
        id=user_b_id,
        email=f"user_b_{user_b_id.hex[:8]}@example.com",
        username=f"user_b_{user_b_id.hex[:8]}",
        hashed_password="dummy_password",
        display_name="Temp User B",
    )
    
    db_session.add(user_a)
    db_session.add(user_b)
    await db_session.commit()
    
    yield user_a, user_b
    
    # Cleanup User A & User B records
    # 1. Deck Items
    await db_session.execute(delete(VocabularyDeckItem).where(
        VocabularyDeckItem.deck_id.in_(
            select(VocabularyDeck.id).where(VocabularyDeck.user_id.in_([user_a_id, user_b_id]))
        )
    ))
    # 2. Decks
    await db_session.execute(delete(VocabularyDeck).where(VocabularyDeck.user_id.in_([user_a_id, user_b_id])))
    # 3. Reviews
    await db_session.execute(delete(VocabularyReview).where(
        VocabularyReview.user_vocabulary_id.in_(
            select(UserVocabulary.id).where(UserVocabulary.user_id.in_([user_a_id, user_b_id]))
        )
    ))
    # 4. User Vocabulary
    await db_session.execute(delete(UserVocabulary).where(UserVocabulary.user_id.in_([user_a_id, user_b_id])))
    # 5. Users
    await db_session.execute(delete(User).where(User.id.in_([user_a_id, user_b_id])))
    await db_session.commit()

@pytest.mark.asyncio
async def test_empty_basic_catalog_does_not_mark_user_as_seeded(
    db_session: AsyncSession,
    temp_users,
):
    user_a, _ = temp_users

    await vocabulary_crud.ensure_basic_words_for_user(db_session, user_a.id)
    await db_session.refresh(user_a)

    assert user_a.has_seeded_basic_words is False


@pytest.mark.asyncio
async def test_vocabulary_auto_seeding_and_isolation(
    db_session: AsyncSession,
    temp_users,
    basic_vocabulary_catalog,
):
    user_a, user_b = temp_users
    
    # 1. Verify initial count in user_vocabulary is 0 for both users
    cnt_a = await db_session.scalar(select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == user_a.id))
    cnt_b = await db_session.scalar(select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == user_b.id))
    assert cnt_a == 0
    assert cnt_b == 0
    
    # 2. Seed basic 200 words for User A
    await vocabulary_crud.ensure_basic_words_for_user(db_session, user_a.id)
    
    # Verify User A has 200 words, User B still has 0 (isolation of seeding)
    cnt_a_after = await db_session.scalar(select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == user_a.id))
    cnt_b_after = await db_session.scalar(select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == user_b.id))
    assert cnt_a_after == 200
    assert cnt_b_after == 0
    
    # 3. Seed basic 200 words for User B
    await vocabulary_crud.ensure_basic_words_for_user(db_session, user_b.id)
    cnt_b_after_seed = await db_session.scalar(select(func.count(UserVocabulary.id)).where(UserVocabulary.user_id == user_b.id))
    assert cnt_b_after_seed == 200

@pytest.mark.asyncio
async def test_multi_user_srs_isolation(
    db_session: AsyncSession,
    temp_users,
    basic_vocabulary_catalog,
):
    user_a, user_b = temp_users
    
    # Seed words
    await vocabulary_crud.ensure_basic_words_for_user(db_session, user_a.id)
    await vocabulary_crud.ensure_basic_words_for_user(db_session, user_b.id)
    
    # Find a common vocabulary item seeded in both collections
    result_a = await db_session.execute(
        select(UserVocabulary)
        .options(joinedload(UserVocabulary.vocabulary))
        .where(UserVocabulary.user_id == user_a.id)
        .limit(1)
    )
    uv_a = result_a.scalar_one()
    vocab_id = uv_a.vocabulary_id
    
    result_b = await db_session.execute(
        select(UserVocabulary)
        .where(UserVocabulary.user_id == user_b.id, UserVocabulary.vocabulary_id == vocab_id)
    )
    uv_b = result_b.scalar_one()
    
    # Assert they are separate DB rows with their own IDs
    assert uv_a.id != uv_b.id
    uv_b_id = uv_b.id
    
    # Modify User A's SRS state and notes, verify User B's state remains untouched
    uv_a.ease_factor = 2.8
    uv_a.repetitions = 5
    uv_a.notes = "Custom note from User A"
    db_session.add(uv_a)
    await db_session.commit()
    
    # Refresh from database and check User B's state
    result_b_refreshed = await db_session.execute(
        select(UserVocabulary)
        .where(UserVocabulary.id == uv_b_id)
    )
    uv_b_refreshed = result_b_refreshed.scalar_one()
    assert uv_b_refreshed.ease_factor == 2.5
    assert uv_b_refreshed.repetitions == 0
    assert uv_b_refreshed.notes is None

@pytest.mark.asyncio
async def test_deck_and_item_isolation(db_session: AsyncSession, temp_users):
    user_a, user_b = temp_users

    # User A creates a custom deck
    deck_a = VocabularyDeck(
        id=uuid.uuid4(),
        user_id=user_a.id,
        name="User A Travel Deck",
        color="#FF0000"
    )
    db_session.add(deck_a)
    await db_session.commit()
    
    # Get decks for User A and User B
    decks_a = await vocabulary_crud.get_user_decks(db_session, user_a.id)
    decks_b = await vocabulary_crud.get_user_decks(db_session, user_b.id)
    
    assert len(decks_a) == 1
    assert decks_a[0].name == "User A Travel Deck"
    assert len(decks_b) == 0  # Isolation: User B has no decks
    
    # Verify User B cannot fetch User A's deck via general query
    deck_fetched_for_b = await db_session.scalar(
        select(VocabularyDeck).where(VocabularyDeck.id == deck_a.id, VocabularyDeck.user_id == user_b.id)
    )
    assert deck_fetched_for_b is None
