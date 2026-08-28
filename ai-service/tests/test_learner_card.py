from api.services.learner_card import (
    course_suggestions,
    detect_learner_intents,
    render_card_facts,
)

CARD = {
    "display_name": "Thang",
    "native_language": "vi",
    "member_since": "2026-01-04",
    "goal": "career",
    "interest": "technology",
    "cefr_level": "B1",
    "assessed_level": "B2",
    "overall_score": 71.5,
    "total_xp": 4200,
    "numeric_level": 12,
    "rank": "gold",
    "streak_days": 9,
    "lessons_completed": 63,
    "exercises_completed": 812,
    "skills": {
        "speaking": {"score": 44.0, "level": "B1", "exercises": 20},
        "reading": {"score": 78.0, "level": "B2", "exercises": 90},
    },
    "enrolled_courses": [
        {"course_id": "c1", "title": "Business English", "level": "B2", "progress": 40.0}
    ],
    "suggested_courses": [
        {"course_id": "c2", "title": "IELTS Prep", "level": "B2", "description": "d"}
    ],
}


def test_only_relevant_turns_pull_the_card():
    assert detect_learner_intents("How do I use the present perfect?") == set()
    assert detect_learner_intents("Sửa giúp tôi câu này nhé") == set()
    assert "identity" in detect_learner_intents("tên tôi là gì?")
    assert "progress" in detect_learner_intents("trình độ của tôi hiện tại ra sao")
    assert "course" in detect_learner_intents("khóa học nào phù hợp với tôi?")
    assert "course" in detect_learner_intents("what should I learn next?")


def test_facts_render_only_the_slice_the_turn_asked_for():
    courses_only = render_card_facts(CARD, {"course"})
    assert "IELTS Prep" in courses_only
    assert "Business English" in courses_only
    # A course question must not drag the learner's XP and streak into the prompt.
    assert "streak" not in courses_only
    assert "4200" not in courses_only

    progress = render_card_facts(CARD, {"progress"})
    assert "B2" in progress and "4200" in progress and "streak 9 days" in progress
    # Weakest skill first, so the model leads with what needs work.
    assert progress.index("speaking 44.0") < progress.index("reading 78.0")


def test_no_facts_without_intent_or_card():
    assert render_card_facts(CARD, set()) == ""
    assert render_card_facts({}, {"progress"}) == ""


def test_course_rows_are_attached_only_for_course_turns():
    assert course_suggestions(CARD, {"course"})[0]["course_id"] == "c2"
    assert course_suggestions(CARD, {"progress"}) == []
