"""Deterministic original content generation behind a replaceable interface."""

from __future__ import annotations

import hashlib
from typing import Protocol

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


class CourseGenerator(Protocol):
    def generate_courses(
        self,
        plan: CurriculumPlan,
        request: GenerationRequest,
    ) -> list[CourseArtifact]: ...


def _stable_id(*parts: object) -> str:
    payload = "|".join(str(part) for part in parts)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()[:20]


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
            question="Listen, then repeat the target phrase clearly.",
            correct_answer=_generated_example(first),
            explanation="Focus on clear rhythm and complete word sounds.",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 1),
            type="translate",
            ui_type="pronunciation_practice",
            question="Pronounce the target word after the audio.",
            correct_answer=second.word or "",
            explanation="Speak slowly first, then repeat at a natural pace.",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 2),
            type="fill_blank",
            ui_type="dictation",
            question="Listen and type the complete sentence.",
            correct_answer=_generated_example(third),
            hint="Replay the audio and listen for word endings.",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 3),
            type="multiple_choice",
            ui_type="listen_and_choose",
            question="Listen and choose the word you hear.",
            options=_choice_options(lesson, 3),
            correct_answer=fourth.word or "",
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 4),
            type="multiple_choice",
            ui_type="multiple_choice",
            question="Which lesson word best matches the generated definition?",
            options=_choice_options(lesson, 4),
            correct_answer=fifth.word or "",
            explanation=_generated_definition(fifth),
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 5),
            type="matching",
            ui_type="match_word_to_meaning",
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
            question="Complete the sentence: We use {blank} in this topic.",
            correct_answer=seventh.word or "",
            explanation=_generated_definition(seventh),
        ),
        ExerciseArtifact(
            id=_stable_id(*lesson_key, 7),
            type="true_false",
            ui_type="true_or_false",
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


class DeterministicCourseGenerator:
    """Local generator used by tests and deployments without model access."""

    def generate_courses(
        self,
        plan: CurriculumPlan,
        request: GenerationRequest,
    ) -> list[CourseArtifact]:
        courses: list[CourseArtifact] = []
        for planned_course in plan.courses:
            units: list[UnitArtifact] = []
            for planned_unit in planned_course.units:
                lessons: list[LessonArtifact] = []
                for planned_lesson in planned_unit.lessons:
                    vocabulary = [
                        VocabularyArtifact(
                            word=record.word or "",
                            definition=_generated_definition(record),
                            translation_vi=record.translation_vi,
                            example=_generated_example(record),
                            part_of_speech=record.part_of_speech,
                            difficulty_level=planned_course.level,
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
                                record.source_content_usage
                                or record.content_usage.value
                            ),
                        )
                        for record in planned_lesson.vocabulary
                    ]
                    exercises = _configured_exercises(planned_lesson, request)

                    lessons.append(
                        LessonArtifact(
                            title=planned_lesson.title,
                            description=(
                                f"Practice {planned_course.level.value} vocabulary "
                                f"for {planned_lesson.topic.replace('_', ' ')}."
                            ),
                            order_index=planned_lesson.order_index,
                            vocabulary=vocabulary,
                            exercises=exercises,
                            estimated_minutes=max(10, request.exercises_per_lesson * 2),
                            xp_reward=request.exercises_per_lesson * 2,
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
                    tags=[
                        "generated",
                        "cefr",
                        planned_course.level.value,
                    ],
                    units=units,
                )
            )
        return courses
