"""The CEFR promotion exam: eligibility, paper, server-side grading, cooldown."""

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import patch
from uuid import uuid4

import pytest
from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from app.core.database import Base
from app.models.content import GrammarItem, QuestionItem, TestExam
from app.models.learner_state import LearnerStateProfile
from app.models.progress import Streak
from app.models.proficiency import (
    LevelAssessmentTest,
    LevelExamAttempt,
    UserLevelHistory,
    UserProficiencyProfile,
    UserSkillScore,
)
from app.models.user import User
from app.routes import level_exam as routes
from app.services import level_exam_service as exam


@pytest.fixture
async def db():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    tables = [
        User.__table__,
        UserProficiencyProfile.__table__,
        UserSkillScore.__table__,
        UserLevelHistory.__table__,
        LevelAssessmentTest.__table__,
        LevelExamAttempt.__table__,
        LearnerStateProfile.__table__,
        GrammarItem.__table__,
        QuestionItem.__table__,
        TestExam.__table__,
        Streak.__table__,
    ]
    async with engine.begin() as conn:
        await conn.run_sync(lambda c: Base.metadata.create_all(c, tables=tables))
    factory = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with factory() as session:
        yield session
    await engine.dispose()


@pytest.fixture
async def user(db):
    row = User(
        email=f"exam_{uuid4().hex[:6]}@example.com",
        username=f"exam_{uuid4().hex[:6]}",
        hashed_password="x",
        level="A1",
        certified_level="A1",
    )
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return row


@pytest.fixture
def ready():
    """Readiness has its own test; the rest of the flow assumes the learner qualifies."""
    with patch.object(
        exam,
        "requirements_check",
        autospec=True,
        return_value=SimpleNamespace(qualifies_for_next=True, overall_progress=100.0, blockers=[]),
    ):
        yield


async def _bank(db, per_level: dict[str, int]) -> None:
    for level, count in per_level.items():
        for i in range(count):
            db.add(
                QuestionItem(
                    prompt=f"{level} question {i}",
                    question_type="mcq",
                    options=["right", "wrong one", "wrong two", "wrong three"],
                    answer={"correct": "right"},
                    explanation=f"why {level}-{i}",
                    difficulty_level=level,
                    is_active=True,
                )
            )
    await db.commit()


def _answers(paper, right_levels: set[str]) -> dict[str, str]:
    return {
        q["id"]: ("right" if section["level"] in right_levels else "wrong one")
        for section in paper["sections"]
        for q in section["questions"]
    }


async def _submit(db, user, paper, right_levels):
    return await routes.submit_exam(
        uuid_of(paper), routes.ExamSubmission(answers=_answers(paper, right_levels)), db, user
    )


def uuid_of(paper):
    from uuid import UUID

    return UUID(paper["attempt_id"])


# --- grading primitives -------------------------------------------------------


@pytest.mark.parametrize(
    "answer,expected",
    [
        ({"correct": "B"}, "B"),
        ({"answer": "c"}, "C"),
        (1, "B"),
        ("b", "B"),
        (["B"], "B"),
        ("Z", None),
        (9, None),
        ({"other": "B"}, None),
        (True, None),
    ],
)
def test_correct_option_reads_every_stored_shape(answer, expected):
    question = QuestionItem(question_type="mcq", options=["A", "B", "C"], answer=answer)
    assert exam.correct_option(question) == expected


def test_an_answer_matching_two_options_is_not_gradable():
    question = QuestionItem(question_type="mcq", options=["Yes", "yes ", "No"], answer="yes")
    assert not exam.is_gradable(question)


def test_free_text_questions_are_left_out():
    question = QuestionItem(question_type="essay", options=["A", "B"], answer="A")
    assert not exam.is_gradable(question)


# --- eligibility ---------------------------------------------------------------


async def test_a_fresh_learner_is_not_ready(db, user):
    await _bank(db, {"A2": 5})
    gate = await routes.get_eligibility(db, user)
    assert gate["available"] is False
    assert gate["reason"] == "not_ready"
    assert gate["target_level"] == "A2"


async def test_nothing_above_c2(db, user):
    user.certified_level = "C2"
    await db.commit()
    gate = await routes.get_eligibility(db, user)
    assert gate["reason"] == "max_level"


async def test_a_bank_that_cannot_fill_the_next_level_says_so(db, user, ready):
    await _bank(db, {"A2": 4})
    gate = await routes.get_eligibility(db, user)
    assert gate["reason"] == "no_questions"
    with pytest.raises(HTTPException) as raised:
        await routes.start_exam(db, user)
    assert raised.value.status_code == 403


async def test_ungradable_questions_do_not_count_toward_a_section(db, user, ready):
    await _bank(db, {"A2": 4})
    db.add(QuestionItem(prompt="?", question_type="mcq", options=["a", "b"], answer="z", difficulty_level="A2"))
    await db.commit()
    assert (await routes.get_eligibility(db, user))["reason"] == "no_questions"


# --- sitting -------------------------------------------------------------------


async def test_the_paper_runs_from_the_next_level_up_and_hides_answers(db, user, ready):
    await _bank(db, {"A1": 5, "A2": 6, "B1": 5, "B2": 3})
    paper = await routes.start_exam(db, user)

    assert [s["level"] for s in paper["sections"]] == ["A2", "B1"]
    assert all(len(s["questions"]) == exam.SECTION_SIZE for s in paper["sections"])
    for section in paper["sections"]:
        for question in section["questions"]:
            assert set(question) == {"id", "level", "question_type", "prompt", "options"}
    started = datetime.fromisoformat(paper["started_at"])
    expires = datetime.fromisoformat(paper["expires_at"])
    assert expires - started == timedelta(seconds=exam.SECONDS_PER_QUESTION * 10)


async def test_starting_again_resumes_the_same_paper(db, user, ready):
    await _bank(db, {"A2": 8})
    first = await routes.start_exam(db, user)
    second = await routes.start_exam(db, user)
    assert first["attempt_id"] == second["attempt_id"]
    assert first["sections"] == second["sections"]
    assert (await routes.get_eligibility(db, user))["reason"] == "in_progress"


async def test_passing_certifies_the_highest_unbroken_level(db, user, ready):
    await _bank(db, {"A2": 5, "B1": 5, "B2": 5})
    paper = await routes.start_exam(db, user)
    result = await _submit(db, user, paper, {"A2", "B1"})

    assert result["passed"] is True
    assert result["result_level"] == "B1"
    assert result["certified_level"] == "B1"
    assert result["level"] == "B1"
    assert result["level_verified"] is True
    assert [s["passed"] for s in result["sections"]] == [True, True, False]

    history = (await db.execute(select(UserLevelHistory))).scalars().all()
    assert [(h.previous_level, h.new_level, h.change_type) for h in history] == [("A1", "B1", "promotion")]
    record = (await db.execute(select(LevelAssessmentTest))).scalar_one()
    assert (record.test_type, record.assessed_level, record.level_changed) == ("promotion", "B1", True)
    epoch = (await db.execute(select(LearnerStateProfile.state_epoch))).scalar_one()
    assert epoch == 1


async def test_a_gap_stops_the_jump(db, user, ready):
    await _bank(db, {"A2": 5, "B1": 5, "B2": 5})
    paper = await routes.start_exam(db, user)
    result = await _submit(db, user, paper, {"A2", "B2"})
    assert result["result_level"] == "A2"
    assert user.certified_level == "A2"


async def test_a_chosen_working_level_above_the_result_is_kept(db, user, ready):
    user.level = "C1"
    await db.commit()
    await _bank(db, {"A2": 5, "B1": 5})
    paper = await routes.start_exam(db, user)
    result = await _submit(db, user, paper, {"A2", "B1"})
    assert (result["level"], result["certified_level"], result["level_verified"]) == ("C1", "B1", False)


async def test_failing_changes_nothing_and_starts_the_cooldown(db, user, ready):
    await _bank(db, {"A2": 5, "B1": 5})
    paper = await routes.start_exam(db, user)
    result = await _submit(db, user, paper, set())

    assert result["passed"] is False
    assert result["retry_at"] is not None
    assert (user.level, user.certified_level) == ("A1", "A1")
    assert (await db.execute(select(UserLevelHistory))).scalars().all() == []

    gate = await routes.get_eligibility(db, user)
    assert gate["reason"] == "cooldown"
    with pytest.raises(HTTPException) as raised:
        await routes.start_exam(db, user)
    assert raised.value.status_code == 403
    assert raised.value.details["reason"] == "cooldown"
    assert raised.value.details["retry_at"]

    profile = (await db.execute(select(UserProficiencyProfile))).scalar_one()
    later = datetime.now(UTC) + exam.COOLDOWN + timedelta(minutes=1)
    assert (await exam.eligibility(db, user, profile, now=later))["reason"] == "ready"


async def test_a_late_submission_closes_the_sitting_as_expired(db, user, ready):
    await _bank(db, {"A2": 5})
    paper = await routes.start_exam(db, user)
    attempt = await db.get(LevelExamAttempt, uuid_of(paper))
    attempt.expires_at = datetime.now(UTC) - exam.SUBMIT_GRACE - timedelta(seconds=5)
    await db.commit()

    with pytest.raises(HTTPException) as raised:
        await _submit(db, user, paper, {"A2"})
    assert raised.value.status_code == 410
    assert raised.value.details["reason"] == "expired"
    assert attempt.status == "expired"
    assert user.certified_level == "A1"
    assert (await routes.get_eligibility(db, user))["reason"] == "cooldown"


async def test_a_lapsed_sitting_never_submitted_still_counts(db, user, ready):
    await _bank(db, {"A2": 5})
    paper = await routes.start_exam(db, user)
    attempt = await db.get(LevelExamAttempt, uuid_of(paper))
    attempt.expires_at = datetime.now(UTC) - exam.SUBMIT_GRACE - timedelta(seconds=5)
    await db.commit()
    assert (await routes.get_eligibility(db, user))["reason"] == "cooldown"


async def test_a_sitting_is_graded_once_and_only_by_its_owner(db, user, ready):
    await _bank(db, {"A2": 5})
    paper = await routes.start_exam(db, user)
    stranger = User(email="s@example.com", username="stranger", hashed_password="x", level="A1")
    db.add(stranger)
    await db.commit()

    with pytest.raises(HTTPException) as raised:
        await _submit(db, stranger, paper, {"A2"})
    assert raised.value.status_code == 404

    await _submit(db, user, paper, {"A2"})
    with pytest.raises(HTTPException) as raised:
        await _submit(db, user, paper, {"A2"})
    assert raised.value.status_code == 409


async def test_the_review_shows_answers_only_after_closing(db, user, ready):
    await _bank(db, {"A2": 5})
    paper = await routes.start_exam(db, user)
    with pytest.raises(HTTPException) as raised:
        await routes.get_exam_result(uuid_of(paper), db, user)
    assert raised.value.status_code == 409

    await _submit(db, user, paper, {"A2"})
    review = await routes.get_exam_result(uuid_of(paper), db, user)
    assert len(review["questions"]) == 5
    assert all(q["correct_answer"] == "right" and q["is_correct"] for q in review["questions"])
    assert all(q["explanation"].startswith("why A2") for q in review["questions"])


async def test_an_index_answer_is_graded_like_the_option_text(db, user, ready):
    await _bank(db, {"A2": 5})
    paper = await routes.start_exam(db, user)
    answers = {q["id"]: 0 for s in paper["sections"] for q in s["questions"]}
    result = await routes.submit_exam(uuid_of(paper), routes.ExamSubmission(answers=answers), db, user)
    assert result["result_level"] == "A2"


async def test_a_curated_exam_narrows_the_pool_and_sets_the_pass_mark(db, user, ready):
    await _bank(db, {"A2": 10})
    ids = [str(q.id) for q in (await db.execute(select(QuestionItem))).scalars()][:5]
    db.add(TestExam(title="A2 exam", level="A2", passing_score=100, question_ids=ids, is_published=True))
    await db.commit()

    paper = await routes.start_exam(db, user)
    assert {q["id"] for q in paper["sections"][0]["questions"]} == set(ids)
    assert paper["sections"][0]["pass_percent"] == 100

    answers = _answers(paper, {"A2"})
    answers[ids[0]] = "wrong one"  # 4/5 = 80% < 100%
    result = await routes.submit_exam(uuid_of(paper), routes.ExamSubmission(answers=answers), db, user)
    assert result["passed"] is False
