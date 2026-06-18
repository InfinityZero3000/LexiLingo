from api.models.content_agent import GenerationRequest
from api.services.content_agent.adapters import normalize_source_records
from api.services.content_agent.generator import DeterministicCourseGenerator
from api.services.content_agent.planner import plan_curriculum


def _records():
    return normalize_source_records(
        [
            {
                "record_id": f"upload:{index}",
                "word": f"word{index:02d}",
                "part_of_speech": "noun",
                "declared_cefr": "A1",
                "declared_topic": "daily_life",
                "definition": f"Owned definition {index}",
                "example": f"Owned example {index}",
            }
            for index in range(10)
        ],
        source_name="admin_upload",
    )


def test_generator_produces_default_exercise_mix_with_stable_ids():
    request = GenerationRequest(
        levels=["A1"],
        units_per_course=1,
        lessons_per_unit=1,
    )
    plan = plan_curriculum(_records(), request)
    generator = DeterministicCourseGenerator()

    first = generator.generate_courses(plan, request)
    second = generator.generate_courses(plan, request)

    exercises = first[0].units[0].lessons[0].exercises
    assert first == second
    assert len(exercises) == 10
    assert sum(item.ui_type in {"speaking_repeat", "pronunciation_practice"} for item in exercises) == 2
    assert sum(item.ui_type in {"dictation", "listen_and_choose"} for item in exercises) == 2
    assert len({item.id for item in exercises}) == 10
    assert all(item.question and item.correct_answer for item in exercises)

    choice_exercises = [item for item in exercises if item.type == "multiple_choice"]
    assert choice_exercises
    assert all(item.options and item.correct_answer in item.options for item in choice_exercises)


def test_generator_never_uses_restricted_metadata_body():
    records = [
        *_records(),
            *normalize_source_records(
                [
                    {
                        "record_id": "wikidata:Q61509",
                        "title": "Travel planning",
                        "declared_cefr": "A1",
                        "declared_topic": "daily_life",
                        "body": "RESTRICTED-SOURCE-BODY-MARKER",
                        "metadata": {"article_body": "RESTRICTED-METADATA-MARKER"},
                    }
                ],
                source_name="wikidata",
            ),
        ]
    request = GenerationRequest(
        levels=["A1"],
        units_per_course=1,
        lessons_per_unit=1,
    )
    plan = plan_curriculum(records, request)

    courses = DeterministicCourseGenerator().generate_courses(plan, request)
    serialized = courses[0].model_dump_json()

    assert "RESTRICTED-SOURCE-BODY-MARKER" not in serialized
    assert "RESTRICTED-METADATA-MARKER" not in serialized


def test_generator_honors_configured_speaking_and_listening_mix():
    request = GenerationRequest(
        levels=["A1"],
        units_per_course=1,
        lessons_per_unit=1,
        exercises_per_lesson=8,
        exercise_mix={"speaking": 1, "listening": 3},
    )
    plan = plan_curriculum(_records(), request)

    exercises = DeterministicCourseGenerator().generate_courses(
        plan, request
    )[0].units[0].lessons[0].exercises

    assert len(exercises) == 8
    assert (
        sum(
            item.ui_type in {"speaking_repeat", "pronunciation_practice"}
            for item in exercises
        )
        == 1
    )
    assert (
        sum(
            item.ui_type in {"dictation", "listen_and_choose"}
            for item in exercises
        )
        == 3
    )
