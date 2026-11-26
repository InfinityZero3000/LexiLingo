"""The documented seed steps must leave data the app can actually use."""

from pathlib import Path

from sqlalchemy import func, select

from app.core.sample_data_catalog import SAMPLE_ACHIEVEMENTS
from app.models.content import GrammarItem, QuestionItem
from scripts import seed_questions as seed
from scripts.backfill_achievements import BADGE_FILES

BADGES_DIR = Path(__file__).resolve().parents[2] / "flutter-app/assets/badges"


def test_every_sample_achievement_has_a_slug_with_a_bundled_badge() -> None:
    for achievement in SAMPLE_ACHIEVEMENTS:
        badge = BADGE_FILES.get(achievement.get("slug", ""))
        assert badge, achievement["name"]
        assert (BADGES_DIR / badge).is_file(), badge


async def test_question_seed_fills_an_empty_database_and_is_repeatable(db_session):
    counts = []
    for _ in range(2):
        await seed.seed_questions(db_session)
        counts.append(
            (
                await db_session.scalar(select(func.count(QuestionItem.id))),
                await db_session.scalar(select(func.count(GrammarItem.id))),
            )
        )

    written = sum(len(items) for items in seed.GRAMMAR_QUESTIONS.values())
    assert counts == [(written, len(seed.GRAMMAR_TOPICS))] * 2


def test_every_seeded_question_can_be_answered_from_its_options() -> None:
    for title, questions in seed.GRAMMAR_QUESTIONS.items():
        for question in questions:
            assert question["options"].count(question["answer"]) == 1, (
                title,
                question["prompt"],
            )


async def test_seeded_questions_keep_their_own_level(db_session):
    await seed.seed_questions(db_session)

    stored = dict(
        (
            await db_session.execute(
                select(QuestionItem.prompt, QuestionItem.difficulty_level)
            )
        ).all()
    )

    assert set(seed.QUESTION_LEVELS) == set(seed.GRAMMAR_QUESTIONS)
    inversion = seed.GRAMMAR_QUESTIONS["Inversion for Emphasis"][0]["prompt"]
    assert stored[inversion] == "C1"
