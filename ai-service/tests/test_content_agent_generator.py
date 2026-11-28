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


def _is_blind_pass(request: httpx.Request) -> bool:
    return "QUESTIONS (one JSON" in request.content.decode()


def _gemini_json(body: dict) -> httpx.Response:
    return httpx.Response(
        200,
        json={"candidates": [{"content": {"parts": [{"text": json.dumps(body)}]}}]},
    )


def _routed(request: httpx.Request, exercises: list[dict], picks: dict[int, int]) -> httpx.Response:
    if _is_blind_pass(request):
        return _gemini_json({"answers": [{"n": n, "index": i} for n, i in picks.items()]})
    return _gemini_response(exercises)


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
        return _routed(request, exercises, {0: 0, 1: 0})

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
    assert lesson.generation_mode == "llm"
    assert lesson.verification == {
        "method": "blind-answer-v1", "checked": 2, "agreed": 2, "dropped": [],
    }


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

    assert GroqMissionGenerator()._model == "qwen/qwen3.8-27b"

    monkeypatch.setenv("CONTENT_AGENT_GROQ_MODEL", "openai/gpt-oss-20b")
    assert GroqMissionGenerator()._model == "openai/gpt-oss-20b"


@pytest.mark.asyncio
async def test_groq_mission_generator_sends_the_qwen_reasoning_override(monkeypatch):
    """Without it qwen writes <think> prose, Groq answers 400 json_validate_failed
    and every content-agent job silently degrades to the deterministic template."""
    from api.services.content_agent import generator as generator_module

    seen: dict = {}

    async def fake_key(estimated_tokens: int = 600):
        return "test-key"

    def handler(request: httpx.Request) -> httpx.Response:
        seen.update(json.loads(request.content))
        return httpx.Response(200, json={"choices": [{"message": {"content": json.dumps(
            {"title": "t", "outcome": "You can book.", "exercises": [{
                "type": "fill_blank", "ui_type": "dictation", "phase": "task_cycle",
                "question": "Type {blank}.", "correct_answer": "room"}]})}}]})

    monkeypatch.setattr(generator_module, "get_available_groq_key", fake_key)
    request = GenerationRequest(levels=["A1"], units_per_course=1, lessons_per_unit=1)
    plan = plan_curriculum(_records(), request)
    gen = generator_module.GroqMissionGenerator(model="qwen/qwen3.8-27b")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await gen._call_model(client, plan.courses[0].units[0].lessons[0],
                              plan.courses[0].level, request)

    assert seen["reasoning_effort"] == "none"
    assert seen["response_format"] == {"type": "json_object"}


def test_non_qwen_generation_model_sends_no_override():
    from api.services.trace_cag.llm_client import _qwen_reasoning_overrides

    assert _qwen_reasoning_overrides("openai/gpt-oss-120b") == {}


def _rich_records(count: int = 10, *, definitions: bool = True, examples: bool = True):
    return normalize_source_records(
        [
            {
                "record_id": f"upload:{index}",
                "word": f"word{index:02d}",
                "part_of_speech": "noun",
                "declared_cefr": "A1",
                "declared_topic": "daily_life",
                **({"definition": f"Meaning number {index}"} if definitions else {}),
                **({"example": f"I like word{index:02d} very much."} if examples else {}),
            }
            for index in range(count)
        ],
        source_name="admin_upload",
    )


def _lesson_exercises(records, *, lessons_per_unit: int = 1):
    request = GenerationRequest(levels=["A1"], units_per_course=1, lessons_per_unit=lessons_per_unit)
    plan = plan_curriculum(records, request)
    return plan, request, plan.courses[0].units[0].lessons


def test_templates_are_marked_and_never_use_the_placeholder_definition():
    from api.services.content_agent.generator import _deterministic_lesson

    plan, request, lessons = _lesson_exercises(_rich_records())
    lesson = _deterministic_lesson(lessons[0], plan.courses[0].level, request)

    assert lesson.generation_mode == "template"
    assert lesson.verification is None
    assert "An original" not in lesson.model_dump_json(exclude={"vocabulary"})


def test_true_or_false_template_is_not_always_true():
    from api.services.content_agent.generator import _base_exercises

    answers = set()
    for order_index in range(12):
        plan, _, lessons = _lesson_exercises(_rich_records())
        lesson = lessons[0].__class__(**{**lessons[0].__dict__, "order_index": order_index})
        item = next(e for e in _base_exercises(lesson) if e and e.ui_type == "true_or_false")
        answers.add(item.correct_answer)
        meaning = item.question.split('means "')[1].rstrip('".')
        target = item.question.split("'")[1]
        owner = next(r for r in lesson.vocabulary if r.word == target)
        assert (meaning == owner.definition) == (item.correct_answer == "True")

    assert answers == {"True", "False"}


def test_matching_template_has_at_least_two_pairs_in_grader_shape():
    from api.services.content_agent.generator import _base_exercises

    _, _, lessons = _lesson_exercises(_rich_records())
    item = next(e for e in _base_exercises(lessons[0]) if e and e.ui_type == "match_word_to_meaning")

    half = len(item.options) // 2
    pairs = [p.split(":", 1) for p in item.correct_answer.split(", ")]
    assert half >= 2 and len(item.options) == half * 2
    assert len(pairs) == half
    assert [k for k, _ in pairs] == item.options[:half]
    assert [v for _, v in pairs] == item.options[half:]


def test_matching_is_dropped_when_pairs_cannot_be_written_safely():
    from api.services.content_agent.generator import _base_exercises

    records = normalize_source_records(
        [
            {
                "record_id": f"upload:{index}",
                "word": f"word{index:02d}",
                "part_of_speech": "noun",
                "declared_cefr": "A1",
                "declared_topic": "daily_life",
                "definition": "a thing, with a comma" if index else "",
            }
            for index in range(10)
        ],
        source_name="admin_upload",
    )
    _, _, lessons = _lesson_exercises(records)

    assert all(not e or e.ui_type != "match_word_to_meaning" for e in _base_exercises(lessons[0]))


def test_exercises_that_need_a_definition_are_dropped_without_one():
    from api.services.content_agent.generator import _base_exercises

    _, _, lessons = _lesson_exercises(_rich_records(definitions=False, examples=False))
    built = [e for e in _base_exercises(lessons[0]) if e]
    ui_types = {e.ui_type for e in built}

    assert not ui_types & {"true_or_false", "match_word_to_meaning", "fill_in_the_blank"}
    assert "An original" not in json.dumps([e.model_dump() for e in built])


@pytest.mark.asyncio
async def test_template_job_never_runs_out_of_exercises_without_definitions():
    request = GenerationRequest(levels=["A1"], units_per_course=1, lessons_per_unit=1)
    plan = plan_curriculum(_rich_records(definitions=False, examples=False), request)

    courses = await DeterministicCourseGenerator().generate_courses(plan, request)

    assert courses[0].units[0].lessons[0].exercises


def _choice(question: str, options: list[str], answer: str, ui_type: str = "multiple_choice") -> dict:
    return {
        "type": "multiple_choice", "ui_type": ui_type, "phase": "task_cycle",
        "question": question, "options": options, "correct_answer": answer,
    }


def _llm_lesson() -> list[dict]:
    return [
        _choice("Capital of France?", ["Paris", "Rome"], "Paris"),
        _choice("Opposite of hot?", ["cold", "warm"], "cold", "collocation_choice"),
        {"type": "fill_blank", "ui_type": "dictation", "phase": "task_cycle",
         "question": "Type {blank}.", "correct_answer": "room"},
        {"type": "fill_blank", "ui_type": "short_writing_answer", "phase": "task_cycle",
         "question": "Write one sentence.", "correct_answer": "I need a room."},
    ]


async def _run_lesson(handler, *, exercises_per_lesson: int = 4):
    request = GenerationRequest(
        levels=["A1"], units_per_course=1, lessons_per_unit=1, exercises_per_lesson=exercises_per_lesson
    )
    plan = plan_curriculum(_rich_records(), request)
    generator = LLMMissionGenerator(api_key="k", max_attempts=1)
    generator._url = "https://gemini.test/generate"
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        lesson = await generator._generate_lesson(
            client, plan.courses[0].units[0].lessons[0], plan.courses[0].level, request
        )
    return generator, lesson


@pytest.mark.asyncio
async def test_blind_pass_drops_the_exercise_whose_key_the_model_disagrees_with():
    exercises = _llm_lesson()

    generator, lesson = await _run_lesson(lambda r: _routed(r, exercises, {0: 0, 1: 1}))

    assert lesson.generation_mode == "llm"
    assert [e.ui_type for e in lesson.exercises] == ["multiple_choice", "dictation", "short_writing_answer"]
    assert lesson.verification["checked"] == 2
    assert lesson.verification["agreed"] == 1
    assert len(lesson.verification["dropped"]) == 1
    assert any("answer key disagreed" in w for w in generator.warnings)


@pytest.mark.asyncio
async def test_blind_pass_never_shows_the_key_to_the_model():
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        if _is_blind_pass(request):
            seen.append(request.content.decode())
        return _routed(request, _llm_lesson(), {0: 0, 1: 0})

    await _run_lesson(handler)

    assert "correct_answer" not in seen[0] and "Capital of France?" in seen[0]
    assert "Write one sentence" not in seen[0]


@pytest.mark.asyncio
async def test_unreachable_blind_pass_falls_back_to_the_template_with_a_warning():
    def handler(request: httpx.Request) -> httpx.Response:
        if _is_blind_pass(request):
            return httpx.Response(500, text="boom")
        return _gemini_response(_llm_lesson())

    generator, lesson = await _run_lesson(handler)

    assert lesson.generation_mode == "template"
    assert lesson.verification is None
    assert any(w.startswith('template fallback for lesson "') for w in generator.warnings)


@pytest.mark.asyncio
async def test_lesson_left_without_a_production_task_falls_back():
    exercises = [
        _choice("Q1?", ["a", "b"], "a"),
        _choice("Q2?", ["a", "b"], "a"),
        _choice("Q3?", ["a", "b"], "a", "collocation_choice"),
        {"type": "true_false", "ui_type": "true_or_false", "question": "Q4 true?",
         "options": ["True", "False"], "correct_answer": "True"},
        {"type": "fill_blank", "ui_type": "fill_in_the_blank", "question": "I {blank} it.",
         "options": ["see", "sea"], "correct_answer": "see"},
    ]

    generator, lesson = await _run_lesson(
        lambda r: _routed(r, exercises, {0: 0, 1: 0, 2: 0, 3: 0, 4: 1}), exercises_per_lesson=5
    )

    assert lesson.generation_mode == "template"
    assert any("survived verification" in w for w in generator.warnings)


@pytest.mark.asyncio
async def test_fallback_warnings_reach_the_job_artifact(monkeypatch):
    from api.services.content_agent.service import ContentAgentService
    from api.services.content_agent.store import ContentAgentStore

    async def boom(*args, **kwargs):
        raise RuntimeError("provider down")

    generator = LLMMissionGenerator(api_key="k", max_attempts=1)
    monkeypatch.setattr(generator, "_call_model", boom)
    store = ContentAgentStore(ttl_seconds=60, max_records=50)
    service = ContentAgentService(store=store, generator=generator)
    request = GenerationRequest(levels=["A1"], units_per_course=1, lessons_per_unit=1)
    await store.append("job-1", _rich_records())

    artifact = await service.generate("job-1", request)

    assert any(
        w.startswith('template fallback for lesson "') and w.endswith("provider down")
        for w in artifact.quality.warnings
    )
    assert artifact.courses[0].units[0].lessons[0].generation_mode == "template"
