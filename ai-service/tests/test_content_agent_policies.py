from datetime import date

import pytest

from api.models.content_agent import CourseArtifact, ExerciseArtifact, LessonArtifact, UnitArtifact
from api.services.content_agent.policies import (
    SOURCE_POLICIES,
    SourcePolicyError,
    apply_source_policy,
    find_missing_production_exercise_lessons,
    get_source_policy,
)


def test_approved_lexical_policy_preserves_only_supported_content_fields():
    record = apply_source_policy(
        "oewn",
        {
            "record_id": "oewn:2025:1",
            "source_url": "https://github.com/globalwordnet/english-wordnet",
            "title": "Open English WordNet",
            "word": "journey",
            "part_of_speech": "noun",
            "definition": "An act of travelling from one place to another.",
            "declared_cefr": "A2",
            "declared_topic": "travel",
            "metadata": {
                "resource_type": "lexical",
                "unapproved_field": "must not survive",
            },
        },
    )

    serialized = record.model_dump_json()
    assert record.content_usage == "full_text"
    assert record.word == "journey"
    assert record.definition.startswith("An act of travelling")
    assert "must not survive" not in serialized


def test_registry_contains_only_approved_dataset_sources_and_compatibility_alias():
    assert set(SOURCE_POLICIES) == {
        "existing_cefr",
        "admin_upload",
        "oewn",
        "cmudict",
        "cefr_j",
        "wikidata",
        "tatoeba",
        "librispeech",
        "common_voice",
    }


@pytest.mark.parametrize(
    "source_name",
    [
        "voa",
        "bbc",
        "british_council",
        "cambridge_english",
        "cambridge_dictionary",
        "oxford",
        "dol",
        "prep",
        "ielts_workshop",
        "wiktionary",
        "conceptnet",
    ],
)
def test_denied_sources_are_unsupported(source_name):
    with pytest.raises(SourcePolicyError, match="Unsupported content source"):
        get_source_policy(source_name)


def test_unknown_and_expired_policies_fail_closed():
    with pytest.raises(SourcePolicyError):
        get_source_policy("not_allowlisted")

    with pytest.raises(SourcePolicyError):
        get_source_policy("oewn", as_of=date(2030, 1, 1))


def _vocabulary():
    return [
        {
            "word": "hotel",
            "definition": "a place to stay",
            "part_of_speech": "noun",
            "difficulty_level": "A1",
        }
    ]


def _course_with_exercises(exercises: list[dict]) -> CourseArtifact:
    return CourseArtifact(
        title="Test course",
        level="A1",
        units=[
            UnitArtifact(
                title="Unit 1",
                order_index=0,
                lessons=[
                    LessonArtifact(
                        title="Mission lesson",
                        order_index=0,
                        vocabulary=_vocabulary(),
                        exercises=[ExerciseArtifact(id=f"ex{i}", **e) for i, e in enumerate(exercises)],
                    )
                ],
            )
        ],
    )


def test_missing_production_exercise_is_flagged():
    course = _course_with_exercises(
        [
            {"type": "multiple_choice", "ui_type": "multiple_choice", "question": "q1", "correct_answer": "a"},
            {"type": "true_false", "ui_type": "true_or_false", "question": "q2", "correct_answer": "True"},
        ]
    )

    errors = find_missing_production_exercise_lessons([course])

    assert len(errors) == 1
    assert "Mission lesson" in errors[0]


def test_lesson_with_production_exercise_passes():
    course = _course_with_exercises(
        [
            {"type": "multiple_choice", "ui_type": "multiple_choice", "question": "q1", "correct_answer": "a"},
            {"type": "fill_blank", "ui_type": "fill_in_the_blank", "question": "q2 {blank}", "correct_answer": "b"},
        ]
    )

    assert find_missing_production_exercise_lessons([course]) == []


def _exercise(ui_type: str, index: int = 0) -> ExerciseArtifact:
    return ExerciseArtifact(
        id=f"e{index}", type="multiple_choice", ui_type=ui_type, question="Q?", correct_answer="a"
    )


def test_lesson_that_lost_exercises_needs_three_and_a_production_task():
    from api.services.content_agent.policies import lesson_survives_verification

    choice = [_exercise("multiple_choice", i) for i in range(3)]
    assert not lesson_survives_verification(choice)
    assert not lesson_survives_verification([_exercise("dictation"), _exercise("multiple_choice", 1)])
    assert lesson_survives_verification(choice[:2] + [_exercise("dictation", 5)])


@pytest.mark.asyncio
async def test_blind_pass_rejects_keys_missing_from_the_options_and_bad_indexes():
    from api.services.content_agent.verification import verify_exercises

    def choice(index: int, options: list[str], answer: str) -> ExerciseArtifact:
        return ExerciseArtifact(
            id=f"c{index}", type="multiple_choice", ui_type="multiple_choice",
            question=f"Q{index}?", options=options, correct_answer=answer,
        )

    items = [choice(0, ["a", "b"], "z"), choice(1, ["a", "b"], "b"), choice(2, ["a", "b"], "a")]

    async def call(prompt: str) -> dict:
        return {"answers": [{"n": 0, "index": 0}, {"n": 1, "index": 9}, {"n": 2, "index": 0}]}

    kept, stats = await verify_exercises(items, level="A1", lesson_title="L", call=call)

    assert [e.id for e in kept] == ["c2"]
    assert stats == {"method": "blind-answer-v1", "checked": 3, "agreed": 1, "dropped": ["c0", "c1"]}


@pytest.mark.asyncio
async def test_blind_pass_retries_once_then_raises():
    from api.services.content_agent.verification import VerificationUnavailable, verify_exercises

    calls = []

    async def call(prompt: str) -> dict:
        calls.append(1)
        raise RuntimeError("down")

    item = ExerciseArtifact(
        id="c", type="multiple_choice", ui_type="multiple_choice",
        question="Q?", options=["a", "b"], correct_answer="a",
    )
    with pytest.raises(VerificationUnavailable):
        await verify_exercises([item], level="A1", lesson_title="L", call=call)
    assert len(calls) == 2
