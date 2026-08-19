import json

import httpx
import pytest

from api.models.content_agent import GenerationRequest
from api.services.content_agent.adapters import normalize_source_records
from api.services.content_agent.generator import (
    PRODUCTION_UI_TYPES,
    DeterministicCourseGenerator,
    LLMMissionGenerator,
)
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


@pytest.mark.asyncio
async def test_generator_produces_default_exercise_mix_with_stable_ids():
    request = GenerationRequest(
        levels=["A1"],
        units_per_course=1,
        lessons_per_unit=1,
    )
    plan = plan_curriculum(_records(), request)
    generator = DeterministicCourseGenerator()

    first = await generator.generate_courses(plan, request)
    second = await generator.generate_courses(plan, request)

    exercises = first[0].units[0].lessons[0].exercises
    assert first == second
    assert len(exercises) == 10
    assert all(item.concept_id and item.concept_id.startswith("vocab:") for item in exercises)
    assert sum(item.ui_type in {"speaking_repeat", "pronunciation_practice"} for item in exercises) == 2
    assert sum(item.ui_type in {"dictation", "listen_and_choose"} for item in exercises) == 2
    assert len({item.id for item in exercises}) == 10
    assert all(item.question and item.correct_answer for item in exercises)

    choice_exercises = [item for item in exercises if item.type == "multiple_choice"]
    assert choice_exercises
    assert all(item.options and item.correct_answer in item.options for item in choice_exercises)


@pytest.mark.asyncio
async def test_generator_never_uses_restricted_metadata_body():
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

    courses = await DeterministicCourseGenerator().generate_courses(plan, request)
    serialized = courses[0].model_dump_json()

    assert "RESTRICTED-SOURCE-BODY-MARKER" not in serialized
    assert "RESTRICTED-METADATA-MARKER" not in serialized


@pytest.mark.asyncio
async def test_generator_honors_configured_speaking_and_listening_mix():
    request = GenerationRequest(
        levels=["A1"],
        units_per_course=1,
        lessons_per_unit=1,
        exercises_per_lesson=8,
        exercise_mix={"speaking": 1, "listening": 3},
    )
    plan = plan_curriculum(_records(), request)

    courses = await DeterministicCourseGenerator().generate_courses(plan, request)
    exercises = courses[0].units[0].lessons[0].exercises

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


def _gemini_response(exercises: list[dict], title="Book a hotel room", outcome="You can book a hotel room."):
    body = json.dumps({"title": title, "outcome": outcome, "exercises": exercises})
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"parts": [{"text": body}]}}]},
    )


@pytest.mark.asyncio
async def test_llm_mission_generator_parses_valid_response_with_phase_and_production():
    exercises = [
        {
            "type": "multiple_choice",
            "ui_type": "multiple_choice",
            "phase": "pre_task",
            "question": "Which situation is this mission about?",
            "options": ["Hotel", "Airport", "Restaurant"],
            "correct_answer": "Hotel",
        },
        {
            "type": "fill_blank",
            "ui_type": "short_writing_answer",
            "phase": "task_cycle",
            "question": "Write a sentence asking for a room for two nights.",
            "correct_answer": "I would like a room for two nights.",
        },
        {
            "type": "fill_blank",
            "ui_type": "fill_in_the_blank",
            "phase": "language_focus",
            "concept_id": "grammar:modal_would_like",
            "question": "I would like {blank} a room.",
            "correct_answer": "to book",
        },
        {
            "type": "true_false",
            "ui_type": "true_or_false",
            "phase": "language_focus",
            "question": "'Book' can be used as a verb meaning to reserve.",
            "options": ["True", "False"],
            "correct_answer": "True",
        },
    ]

    def handler(request: httpx.Request) -> httpx.Response:
        return _gemini_response(exercises)

    request = GenerationRequest(
        levels=["A1"], units_per_course=1, lessons_per_unit=1, exercises_per_lesson=4
    )
    plan = plan_curriculum(_records(), request)
    generator = LLMMissionGenerator(api_key="test-key")
    generator._url = "https://gemini.test/generate"

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        lesson = await generator._generate_lesson(
            client, plan.courses[0].units[0].lessons[0], plan.courses[0].level, request
        )

    assert lesson.title == "Book a hotel room"
    assert lesson.outcome == "You can book a hotel room."
    assert [e.phase for e in lesson.exercises] == [
        "pre_task",
        "task_cycle",
        "language_focus",
        "language_focus",
    ]
    assert lesson.exercises[2].concept_id == "grammar:modal_would_like"
    assert any(e.ui_type in PRODUCTION_UI_TYPES for e in lesson.exercises)


@pytest.mark.asyncio
async def test_llm_mission_generator_falls_back_to_deterministic_on_error():
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(500, text="server error")

    request = GenerationRequest(
        levels=["A1"], units_per_course=1, lessons_per_unit=1, exercises_per_lesson=10
    )
    plan = plan_curriculum(_records(), request)
    generator = LLMMissionGenerator(api_key="test-key", max_attempts=1)
    generator._url = "https://gemini.test/generate"

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        lesson = await generator._generate_lesson(
            client, plan.courses[0].units[0].lessons[0], plan.courses[0].level, request
        )

    assert len(lesson.exercises) == 10
    assert lesson.title == plan.courses[0].units[0].lessons[0].title


@pytest.mark.asyncio
async def test_llm_mission_generator_uses_deterministic_when_no_api_key():
    request = GenerationRequest(levels=["A1"], units_per_course=1, lessons_per_unit=1)
    plan = plan_curriculum(_records(), request)
    generator = LLMMissionGenerator(api_key="")

    courses = await generator.generate_courses(plan, request)

    assert len(courses[0].units[0].lessons[0].exercises) == request.exercises_per_lesson


@pytest.mark.asyncio
async def test_groq_mission_generator_falls_back_when_every_key_is_throttled(
    monkeypatch,
):
    """A throttled pool must cost one lesson its mission, not the whole job."""
    from api.services.content_agent import generator as generator_module

    async def no_key(estimated_tokens: int = 600):
        return None

    monkeypatch.setattr(generator_module, "get_available_groq_key", no_key)

    request = GenerationRequest(levels=["A1"], units_per_course=1, lessons_per_unit=1)
    plan = plan_curriculum(_records(), request)

    # max_attempts=1: the retry backoff is 15s a go and buys the test nothing.
    courses = await generator_module.GroqMissionGenerator(
        max_attempts=1
    ).generate_courses(plan, request)

    exercises = courses[0].units[0].lessons[0].exercises
    assert exercises, "expected the deterministic template, not an empty lesson"


def test_groq_mission_generator_does_not_borrow_the_short_call_model(monkeypatch):
    """The short service calls run GROQ_MODEL with reasoning off; generating a
    whole lesson that way would be a silent quality drop."""
    from api.services.content_agent.generator import GroqMissionGenerator

    monkeypatch.setenv("GROQ_MODEL", "some/other-model")
    monkeypatch.delenv("CONTENT_AGENT_GROQ_MODEL", raising=False)

    assert GroqMissionGenerator()._model == "qwen/qwen3.6-27b"

    monkeypatch.setenv("CONTENT_AGENT_GROQ_MODEL", "openai/gpt-oss-20b")
    assert GroqMissionGenerator()._model == "openai/gpt-oss-20b"
