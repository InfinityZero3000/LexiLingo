import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.course import Course, Lesson, Unit
from app.models.vocabulary import DifficultyLevel, PartOfSpeech, VocabularyItem
from app.services.cefr_level_fit import (
    course_balance,
    course_level_fit,
    level_fit,
    level_profile,
    lookup,
    share_above,
    tokenize,
)

LEXICON = {
    "dog": "A1", "run": "A1", "happy": "A1", "study": "A1",
    "ability": "B2", "approach": "B2", "ubiquitous": "C2", "nuance": "C1",
}


def _profile(counts: dict[str, int]) -> dict:
    full = {level: counts.get(level, 0) for level in ("A1", "A2", "B1", "B2", "C1", "C2")}
    return {"counts": full, "listed": sum(full.values()), "unlisted": 0, "n": sum(full.values())}


def test_tokenize_drops_stopwords_short_words_and_contractions():
    assert tokenize("The dog's not running, it is big!") == ["dog", "running", "big"]


def test_tokenize_skips_vietnamese_segments_but_keeps_english_prompt():
    words = tokenize("Translate to English: 'Cái này bao nhiêu?' Don't worry")
    assert words == ["translate", "english", "worry"]


def test_lookup_exact_first_then_inflections():
    assert lookup("dogs", LEXICON) == "A1"
    assert lookup("running", LEXICON) == "A1"
    assert lookup("happier", LEXICON) == "A1"
    assert lookup("studied", LEXICON) == "A1"
    assert lookup("zzzz", LEXICON) is None
    assert lookup("run", {"run": "B1", "runs": "A1"}) == "B1"


def test_profile_counts_levels_and_unlisted():
    profile = level_profile(["The dogs run", "Ubiquitous ability, qwerty"], LEXICON)
    assert profile["counts"]["A1"] == 2
    assert profile["counts"]["B2"] == 1
    assert profile["counts"]["C2"] == 1
    assert (profile["listed"], profile["unlisted"], profile["n"]) == (4, 1, 5)
    assert share_above(profile, "A1") == 0.5
    assert share_above(profile, "B2", inclusive=True) == 0.5


def test_verdicts():
    assert level_fit(_profile({"A1": 90, "A2": 10}), "A1")["verdict"] == "fits"
    assert level_fit(_profile({"A1": 50, "B2": 50}), "A1")["verdict"] == "too_hard"
    assert level_fit(_profile({"A1": 80, "A2": 15, "C1": 4, "C2": 1}), "C2")["verdict"] == "too_easy"
    assert level_fit(_profile({"A1": 40, "B2": 30, "C1": 30}), "C2")["verdict"] == "fits"
    assert level_fit(_profile({"A1": 29}), "A1")["verdict"] == "unknown"
    assert level_fit(_profile({"A1": 100}), None)["verdict"] == "unknown"
    assert level_fit(_profile({"A1": 100}), "A1")["above_share"] == 0.0


def test_low_level_course_is_never_too_easy():
    assert level_fit(_profile({"A1": 100}), "A2")["verdict"] == "fits"


def _view(exercises: list[dict], **kwargs) -> dict:
    lesson = {"unit": "Unit 1", "title": "L1", "outcome": None, "skill": None, "exercises": exercises}
    return {"title": "T", "level": "A1", "skill": None, "lessons": [{**lesson, **kwargs}]}


def test_course_level_fit_ignores_explanation_and_vietnamese_help():
    exercises = [
        {
            "ui_type": "multiple_choice",
            "question": "dog run happy study " * 8,
            "options": ["dog", "run"],
            "correct_answer": "dog",
            "explanation": "ubiquitous nuance approach ability " * 20,
        },
        {"ui_type": "match_word_to_meaning", "question": "dog", "options": ["dog", "chó"], "correct_answer": "dog:chó"},
    ]
    fit = course_level_fit(_view(exercises), LEXICON)
    assert fit["profile"]["counts"]["C2"] == 0
    assert fit["verdict"] == "fits"
    assert fit["worst_lessons"][0]["title"] == "L1"


def test_balance_flags_unit_without_production_and_skill_mismatch():
    choice = {"ui_type": "multiple_choice", "question": "q", "options": ["a", "b"], "correct_answer": "a"}
    writing = {"ui_type": "short_writing_answer", "question": "Write", "correct_answer": "x"}
    speaking = {"ui_type": "speaking_repeat", "question": "Say", "correct_answer": "x"}
    view = {
        "title": "T",
        "level": "A1",
        "skill": "speaking",
        "lessons": [
            {"unit": "U1", "title": "a", "outcome": "You can order food.", "exercises": [choice, writing]},
            {"unit": "U2", "title": "b", "outcome": "  ", "exercises": [choice, choice]},
            {"unit": "U3", "title": "c", "outcome": "I can say hello", "exercises": [speaking]},
        ],
    }
    balance = course_balance(view)
    assert balance["units_without_production"] == ["U2"]
    assert balance["outcome_share"] == pytest.approx(2 / 3, abs=1e-4)
    assert balance["can_do_outcomes"] == 2
    assert balance["unattributed"] == 3
    assert balance["skills"] == {"writing": 1, "speaking": 1}
    assert balance["declared_skill_exercises"] == 1

    view["skill"] = "listening"
    mismatched = course_balance(view)
    assert mismatched["skill_mismatch"] is True
    assert mismatched["declared_skill_exercises"] == 0


async def _course_with_lesson(db: AsyncSession) -> Course:
    course = Course(title="Quality Course", language="en", level="B2", is_published=True)
    db.add(course)
    await db.flush()
    unit = Unit(course_id=course.id, title="Unit 1", order_index=0)
    db.add(unit)
    await db.flush()
    db.add(
        Lesson(
            course_id=course.id,
            unit_id=unit.id,
            title="Lesson 1",
            order_index=0,
            lesson_type="lesson",
            content={
                "exercises": [
                    {
                        "id": "1",
                        "type": "multiple_choice",
                        "ui_type": "multiple_choice",
                        "question": "dog run happy study",
                        "options": ["dog", "run"],
                        "correct_answer": "dog",
                    }
                ]
            },
        )
    )
    db.add(
        VocabularyItem(
            word="dog",
            definition="an animal",
            part_of_speech=PartOfSpeech.NOUN,
            difficulty_level=DifficultyLevel.A1,
        )
    )
    await db.commit()
    return course


@pytest.mark.asyncio
async def test_quality_endpoint_admin_ok(
    async_client: AsyncClient, admin_headers: dict, db_session: AsyncSession
):
    course = await _course_with_lesson(db_session)
    response = await async_client.get(f"/api/v1/admin/courses/{course.id}/quality", headers=admin_headers)
    assert response.status_code == 200
    data = response.json()["data"]
    assert data["title"] == "Quality Course"
    assert data["level_fit"]["declared"] == "B2"
    assert data["level_fit"]["verdict"] == "unknown"
    assert set(data["level_fit"]["distribution"]) == {"A1", "A2", "B1", "B2", "C1", "C2"}
    assert data["balance"]["lessons"] == 1


@pytest.mark.asyncio
async def test_quality_endpoint_unknown_course_404(async_client: AsyncClient, admin_headers: dict):
    response = await async_client.get(
        "/api/v1/admin/courses/00000000-0000-0000-0000-000000000000/quality", headers=admin_headers
    )
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_quality_endpoint_learner_forbidden(
    async_client: AsyncClient, auth_headers: dict, db_session: AsyncSession
):
    course = await _course_with_lesson(db_session)
    response = await async_client.get(f"/api/v1/admin/courses/{course.id}/quality", headers=auth_headers)
    assert response.status_code == 403


def test_file_lexicon_keeps_lowest_level_and_variants(tmp_path):
    from app.services.cefr_level_fit import load_lexicon_file

    path = tmp_path / "lex.jsonl"
    path.write_text(
        '{"word": "color", "variants": ["color", "colour"], "cefr": "A1"}\n'
        '{"word": "color", "variants": ["color"], "cefr": "B2"}\n'
        '{"word": "a.m.", "variants": ["a.m."], "cefr": "A1"}\n'
    )
    assert load_lexicon_file(path) == {"color": "A1", "colour": "A1"}
