"""Content generation behind a replaceable interface: deterministic templates
or an LLM-backed mission generator, both producing the same artifact shape."""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
from typing import Protocol

import httpx
from pydantic import ValidationError

from api.models.content_agent import (
    CourseArtifact,
    ExerciseArtifact,
    GenerationRequest,
    LessonArtifact,
    NormalizedSourceRecord,
    UnitArtifact,
    VocabularyArtifact,
)
from api.services.content_agent.planner import (
    CurriculumPlan,
    PlannedLesson,
)

logger = logging.getLogger(__name__)


class CourseGenerator(Protocol):
    async def generate_courses(
        self,
        plan: CurriculumPlan,
        request: GenerationRequest,
    ) -> list[CourseArtifact]: ...


def _stable_id(*parts: object) -> str:
    payload = "|".join(str(part) for part in parts)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:20]


def _vocab_concept_id(record: NormalizedSourceRecord) -> str | None:
    if not record.word:
        return None
    slug = "_".join(record.word.strip().lower().split())
    return f"vocab:{slug}" if slug else None


def _generated_definition(record: NormalizedSourceRecord) -> str:
    if record.definition:
        return record.definition
    level = record.declared_cefr.value if record.declared_cefr else "CEFR"
    topic = record.declared_topic.replace("_", " ")
    return f"An original {level}-level word or phrase for discussing {topic}."


def _generated_example(record: NormalizedSourceRecord) -> str:
    if record.example:
        return record.example
    topic = record.declared_topic.replace("_", " ")
    return f"We use {record.word} while talking about {topic}."


def _choice_options(
    lesson: PlannedLesson,
    target_index: int,
) -> list[str]:
    words = [record.word or "" for record in lesson.vocabulary]
    target = words[target_index % len(words)]
    start = target_index % len(words)
    options: list[str] = []
    for offset in range(len(words)):
        candidate = words[(start + offset) % len(words)]
        if candidate and candidate not in options:
            options.append(candidate)
        if len(options) == 4:
            break
    if target not in options:
        options[-1] = target
    return sorted(options)


def _base_exercises(lesson: PlannedLesson) -> list[ExerciseArtifact]:
    vocabulary = list(lesson.vocabulary)
    first = vocabulary[0]
    second = vocabulary[1]
    third = vocabulary[2]
    fourth = vocabulary[3]
    fifth = vocabulary[4]
    sixth = vocabulary[5]
    seventh = vocabulary[6]
    eighth = vocabulary[7]
    lesson_key = (
        lesson.level.value,
        lesson.topic,
        lesson.order_index,
        ",".join(record.record_id for record in vocabulary),
    )

    exercises = [
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 0),
            type="translate",
            ui_type="speaking_repeat",
            concept_id=_vocab_concept_id(first),
            question="Listen, then repeat the target phrase clearly.",
            correct_answer=_generated_example(first),
            explanation="Focus on clear rhythm and complete word sounds.",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 1),
            type="translate",
            ui_type="pronunciation_practice",
            concept_id=_vocab_concept_id(second),
            question="Pronounce the target word after the audio.",
            correct_answer=second.word or "",
            explanation="Speak slowly first, then repeat at a natural pace.",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 2),
            type="fill_blank",
            ui_type="dictation",
            concept_id=_vocab_concept_id(third),
            question="Listen and type the complete sentence.",
            correct_answer=_generated_example(third),
            hint="Replay the audio and listen for word endings.",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 3),
            type="multiple_choice",
            ui_type="listen_and_choose",
            concept_id=_vocab_concept_id(fourth),
            question="Listen and choose the word you hear.",
            options=_choice_options(lesson, 3),
            correct_answer=fourth.word or "",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 4),
            type="multiple_choice",
            ui_type="multiple_choice",
            concept_id=_vocab_concept_id(fifth),
            question="Which lesson word best matches the generated definition?",
            options=_choice_options(lesson, 4),
            correct_answer=fifth.word or "",
            explanation=_generated_definition(fifth),
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 5),
            type="matching",
            ui_type="match_word_to_meaning",
            concept_id=_vocab_concept_id(sixth),
            question="Match the lesson word with its generated meaning.",
            options=[
                sixth.word or "",
                _generated_definition(sixth),
            ],
            correct_answer=f"{sixth.word}:{_generated_definition(sixth)}",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 6),
            type="fill_blank",
            ui_type="fill_in_the_blank",
            concept_id=_vocab_concept_id(seventh),
            question="Complete the sentence: We use {blank} in this topic.",
            correct_answer=seventh.word or "",
            explanation=_generated_definition(seventh),
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 7),
            type="true_false",
            ui_type="true_or_false",
            concept_id=_vocab_concept_id(eighth),
            question=(
                f"The word '{eighth.word}' belongs to the "
                f"{lesson.topic.replace('_', ' ')} topic."
            ),
            options=["True", "False"],
            correct_answer="True",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 8),
            type="translate",
            ui_type="translation_choice",
            concept_id=_vocab_concept_id(first),
            question=(
                f"Choose the English lesson word for: "
                f"{first.translation_vi or _generated_definition(first)}"
            ),
            options=_choice_options(lesson, 0),
            correct_answer=first.word or "",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 9),
            type="reorder",
            ui_type="arrange_the_sentence",
            concept_id=_vocab_concept_id(second),
            question="Arrange the words to form the sentence you hear.",
            options=_generated_example(second).rstrip(".").split(),
            correct_answer=_generated_example(second),
        ),
    ]
    return exercises


def _configured_exercises(
    lesson: PlannedLesson,
    request: GenerationRequest,
) -> list[ExerciseArtifact]:
    base = _base_exercises(lesson)
    groups = {
        "speaking": base[:2],
        "listening": base[2:4],
        "knowledge": base[4:],
    }
    selected: list[ExerciseArtifact] = []

    def append_from(group_name: str, count: int) -> None:
        templates = groups[group_name]
        for index in range(count):
            exercise = templates[index % len(templates)].model_copy(deep=True)
            exercise.id = _stable_id(
                lesson.level.value,
                lesson.topic,
                lesson.order_index,
                group_name,
                index,
            )
            selected.append(exercise)

    append_from("speaking", request.exercise_mix.speaking)
    append_from("listening", request.exercise_mix.listening)
    append_from(
        "knowledge",
        request.exercises_per_lesson
        - request.exercise_mix.speaking
        - request.exercise_mix.listening,
    )
    return selected


def _deterministic_vocabulary(
    planned_lesson: PlannedLesson,
    level: object,
) -> list[VocabularyArtifact]:
    return [
        VocabularyArtifact(
            word=record.word or "",
            definition=_generated_definition(record),
            translation_vi=record.translation_vi,
            example=_generated_example(record),
            part_of_speech=record.part_of_speech,
            difficulty_level=level,
            topic=record.declared_topic,
            source_name=record.source_name,
            source_url=record.source_url,
            license_mode=record.license_mode.value,
            source_checksum=record.checksum,
            source_version=record.source_version,
            source_record_id=record.source_record_id,
            license_id=record.license_id,
            license_url=record.license_url,
            attribution_text=record.attribution_text,
            raw_checksum=record.raw_checksum,
            record_checksum=record.checksum,
            lineage=record.lineage,
            content_usage=(
                record.source_content_usage or record.content_usage.value
            ),
        )
        for record in planned_lesson.vocabulary
    ]


def _deterministic_lesson(
    planned_lesson: PlannedLesson,
    level: object,
    request: GenerationRequest,
) -> LessonArtifact:
    return LessonArtifact(
        title=planned_lesson.title,
        description=(
            f"Practice {level.value} vocabulary "
            f"for {planned_lesson.topic.replace('_', ' ')}."
        ),
        order_index=planned_lesson.order_index,
        vocabulary=_deterministic_vocabulary(planned_lesson, level),
        exercises=_configured_exercises(planned_lesson, request),
        estimated_minutes=max(10, request.exercises_per_lesson * 2),
        xp_reward=request.exercises_per_lesson * 2,
    )


class DeterministicCourseGenerator:
    """Local generator used by tests and deployments without model access."""

    async def generate_courses(
        self,
        plan: CurriculumPlan,
        request: GenerationRequest,
    ) -> list[CourseArtifact]:
        courses: list[CourseArtifact] = []
        for planned_course in plan.courses:
            units: list[UnitArtifact] = []
            for planned_unit in planned_course.units:
                lessons: list[LessonArtifact] = [
                    _deterministic_lesson(planned_lesson, planned_course.level, request)
                    for planned_lesson in planned_unit.lessons
                ]
                units.append(
                    UnitArtifact(
                        title=planned_unit.title,
                        description=(
                            f"Topic-based {planned_course.level.value} practice."
                        ),
                        order_index=planned_unit.order_index,
                        lessons=lessons,
                    )
                )
            courses.append(
                CourseArtifact(
                    title=planned_course.title,
                    description=planned_course.description,
                    level=planned_course.level,
                    tags=[
                        "generated",
                        "cefr",
                        planned_course.level.value,
                    ],
                    units=units,
                )
            )
        return courses


PRODUCTION_UI_TYPES: frozenset[str] = frozenset(
    {
        "fill_in_the_blank",
        "dictation",
        "grammar_correction",
        "short_writing_answer",
        "dialogue_completion",
        "speaking_repeat",
        "pronunciation_practice",
    }
)

_GEMINI_URL_TEMPLATE = (
    "https://generativelanguage.googleapis.com/v1beta/models/"
    "{model}:generateContent?key={api_key}"
)


def _mission_prompt(
    planned_lesson: PlannedLesson,
    level: object,
    request: GenerationRequest,
) -> str:
    words = ", ".join(
        f"{record.word} ({record.translation_vi})" if record.translation_vi else record.word or ""
        for record in planned_lesson.vocabulary
        if record.word
    )
    situation = planned_lesson.topic.replace("_", " ")
    production_list = ", ".join(sorted(PRODUCTION_UI_TYPES))
    return f"""
    Design one Task-Based Language Teaching (TBLT) mission lesson for an English learning app.

    Context:
    - CEFR Level: {level.value}
    - Situation/theme: {situation}
    - Target vocabulary to weave in naturally: {words}
    - Total exercises required: exactly {request.exercises_per_lesson}

    A "mission" is a real-world task the learner completes using English (e.g. ordering food,
    booking a hotel room, writing a short apology email) — not a bare grammar drill. Follow the
    TBLT 3-phase structure:
    1. pre_task — 1 exercise that introduces the situation/vocabulary (recognition is fine here).
    2. task_cycle — the majority of exercises: the learner produces language to progress through
       the situation.
    3. language_focus — 1-2 exercises at the end that isolate a grammar/vocabulary point that came
       up during the task.

    Rules:
    1. Return a JSON object with keys "title", "outcome", "exercises".
    2. "title" is a short mission title (not a grammar topic name), e.g. "Book a hotel room by phone".
    3. "outcome" is one can-do sentence starting with "You can...", describing what the learner will
       be able to do after this mission.
    4. "exercises" is a list of exactly {request.exercises_per_lesson} objects, each matching:
       {{
         "type": "multiple_choice" | "true_false" | "fill_blank" | "translate" | "matching" | "reorder",
         "ui_type": one of the 20 supported UI types (multiple_choice, true_or_false,
           fill_in_the_blank, arrange_the_sentence, translation_choice, dialogue_completion,
           collocation_choice, dictation, speaking_repeat, vocabulary_flashcard,
           grammar_correction, image_based_choice, listen_and_choose, pronunciation_practice,
           reading_comprehension, short_writing_answer, categorization, match_word_to_meaning,
           cognitive_fluidity, match_word_meaning),
         "phase": "pre_task" | "task_cycle" | "language_focus",
         "concept_id": "...", // stable slug for the single grammar point or vocabulary word this
           exercise tests, e.g. "grammar:past_simple", "grammar:present_perfect", "vocab:hotel".
           Use "grammar:<snake_case_point>" when the exercise is testing a grammar structure, or
           "vocab:<word_lowercase>" when it is purely testing recall of one target word.
         "question": "...", // use the literal string '{{blank}}' for any gap-fill/dictation/dialogue exercise
         "options": [...],  // only for choice/matching-type exercises
         "correct_answer": "...",
         "explanation": "..." // optional, brief
       }}
    5. At least ONE exercise must use a production ui_type from this list: {production_list}.
       Recognition-only (pure multiple-choice) missions are not acceptable.
    6. Exercises must stay connected to the single situation/theme above — do not generate
       unrelated single-sentence grammar drills.
    7. Difficulty must match {level.value} CEFR level.
    """


class LLMMissionGenerator:
    """Mission-based generator: one LLM call per lesson, TBLT-shaped output.

    Falls back to the deterministic generator per-lesson on any error (missing
    API key, network failure, malformed response) so a job never fails outright
    because of a single bad LLM call.
    """

    def __init__(
        self,
        api_key: str,
        model: str = "gemini-2.5-flash",
        timeout_seconds: float = 45.0,
        max_attempts: int = 3,
    ) -> None:
        self._api_key = api_key
        self._url = _GEMINI_URL_TEMPLATE.format(model=model, api_key=api_key)
        self._timeout_seconds = timeout_seconds
        self._max_attempts = max_attempts

    async def generate_courses(
        self,
        plan: CurriculumPlan,
        request: GenerationRequest,
    ) -> list[CourseArtifact]:
        if not self._api_key:
            return await DeterministicCourseGenerator().generate_courses(plan, request)

        courses: list[CourseArtifact] = []
        async with httpx.AsyncClient() as client:
            for planned_course in plan.courses:
                units: list[UnitArtifact] = []
                for planned_unit in planned_course.units:
                    lessons: list[LessonArtifact] = []
                    for planned_lesson in planned_unit.lessons:
                        lessons.append(
                            await self._generate_lesson(
                                client, planned_lesson, planned_course.level, request
                            )
                        )
                    units.append(
                        UnitArtifact(
                            title=planned_unit.title,
                            description=(
                                f"Topic-based {planned_course.level.value} practice."
                            ),
                            order_index=planned_unit.order_index,
                            lessons=lessons,
                        )
                    )
                courses.append(
                    CourseArtifact(
                        title=planned_course.title,
                        description=planned_course.description,
                        level=planned_course.level,
                        tags=["generated", "mission", planned_course.level.value],
                        units=units,
                    )
                )
        return courses

    async def _generate_lesson(
        self,
        client: httpx.AsyncClient,
        planned_lesson: PlannedLesson,
        level: object,
        request: GenerationRequest,
    ) -> LessonArtifact:
        try:
            raw = await self._call_gemini(client, planned_lesson, level, request)
            return self._to_lesson_artifact(raw, planned_lesson, level, request)
        except (httpx.HTTPError, ValueError, ValidationError, KeyError) as exc:
            logger.warning(
                "LLM mission generation failed for lesson '%s', falling back to "
                "deterministic template: %s",
                planned_lesson.title,
                exc,
            )
            return _deterministic_lesson(planned_lesson, level, request)

    async def _call_gemini(
        self,
        client: httpx.AsyncClient,
        planned_lesson: PlannedLesson,
        level: object,
        request: GenerationRequest,
    ) -> dict:
        payload = {
            "contents": [
                {"parts": [{"text": _mission_prompt(planned_lesson, level, request)}]}
            ],
            "generationConfig": {"responseMimeType": "application/json"},
        }
        last_error: Exception | None = None
        for attempt in range(self._max_attempts):
            try:
                response = await client.post(
                    self._url, json=payload, timeout=self._timeout_seconds
                )
            except httpx.HTTPError as exc:
                last_error = exc
                if attempt < self._max_attempts - 1:
                    await self._backoff(attempt)
                continue

            if response.status_code == 200:
                result = response.json()
                text_response = result["candidates"][0]["content"]["parts"][0]["text"]
                return json.loads(text_response)
            if response.status_code == 429 or response.status_code >= 500:
                last_error = httpx.HTTPStatusError(
                    f"Gemini returned {response.status_code}",
                    request=response.request,
                    response=response,
                )
                if attempt < self._max_attempts - 1:
                    await self._backoff(attempt)
                continue
            response.raise_for_status()

        raise last_error or RuntimeError("Gemini generation failed with no response")

    @staticmethod
    async def _backoff(attempt: int) -> None:
        await asyncio.sleep(min(15 * (attempt + 1), 30))

    def _to_lesson_artifact(
        self,
        raw: dict,
        planned_lesson: PlannedLesson,
        level: object,
        request: GenerationRequest,
    ) -> LessonArtifact:
        lesson_key = (
            level.value,
            planned_lesson.topic,
            planned_lesson.order_index,
            ",".join(record.record_id for record in planned_lesson.vocabulary),
        )
        exercises = [
            ExerciseArtifact(
                id=_stable_id(*lesson_key, index),
                type=raw_exercise["type"],
                ui_type=raw_exercise["ui_type"],
                phase=raw_exercise.get("phase", "task_cycle"),
                concept_id=raw_exercise.get("concept_id"),
                question=raw_exercise["question"],
                options=raw_exercise.get("options"),
                correct_answer=raw_exercise["correct_answer"],
                explanation=raw_exercise.get("explanation"),
            )
            for index, raw_exercise in enumerate(raw["exercises"])
        ]
        return LessonArtifact(
            title=raw.get("title") or planned_lesson.title,
            description=(
                f"Mission: {planned_lesson.topic.replace('_', ' ')} ({level.value})."
            ),
            outcome=raw.get("outcome"),
            order_index=planned_lesson.order_index,
            vocabulary=_deterministic_vocabulary(planned_lesson, level),
            exercises=exercises,
            estimated_minutes=max(10, request.exercises_per_lesson * 2),
            xp_reward=request.exercises_per_lesson * 2,
        )
