"""Which CEFR skill a single exercise measures.

Real four-skill assessments tag the *item*, not the lesson: CEFR reports
listening, reading, speaking and writing on separate scales precisely because a
learner's profile is uneven across them, and the Duolingo English Test derives
its four subscores from per-task constructs rather than from the section a task
happens to sit in. LexiLingo credited a whole lesson to one label, so 216 of its
441 writing exercises counted as reading and its 49 listening exercises counted
as nothing at all.

The rules below are deliberately unwilling to guess. A `ui_type` that could
plausibly measure two skills defers to the lesson's own label, and when the
label does not help it returns None and the exercise credits nothing — an
unmeasured item is cheaper than a wrongly measured one, because a wrong skill
is silent and keeps crediting the wrong pillar until somebody re-reads it.
"""

from __future__ import annotations

from app.schemas.proficiency import SkillType

# Templates whose ui_type settles the skill on its own. dictation and
# listen_and_choose are the only two that play anything (they synthesise their
# own text through SpeakIconButton), so audio cannot be faked into the others.
FIXED_SKILL: dict[str, SkillType] = {
    "dictation": SkillType.LISTENING,
    "listen_and_choose": SkillType.LISTENING,
    "speaking_repeat": SkillType.SPEAKING,
    "pronunciation_practice": SkillType.SPEAKING,
    "reading_comprehension": SkillType.READING,
}

# Templates that measure whichever of these the lesson says it is measuring.
# The lesson label only wins if it names one of them: a short writing task in a
# lesson labelled `reading` is still writing.
CANDIDATE_SKILLS: dict[str, frozenset[SkillType]] = {
    "short_writing_answer": frozenset({SkillType.WRITING, SkillType.SPEAKING}),
    "grammar_correction": frozenset({SkillType.GRAMMAR, SkillType.WRITING}),
    "dialogue_completion": frozenset(
        {SkillType.READING, SkillType.GRAMMAR, SkillType.SPEAKING}
    ),
    "translation_choice": frozenset({SkillType.VOCABULARY, SkillType.READING}),
    "vocabulary_flashcard": frozenset({SkillType.VOCABULARY}),
    "match_word_to_meaning": frozenset({SkillType.VOCABULARY}),
    "cognitive_fluidity": frozenset({SkillType.VOCABULARY}),
    "collocation_choice": frozenset({SkillType.VOCABULARY}),
    "categorization": frozenset({SkillType.VOCABULARY, SkillType.READING}),
    "arrange_the_sentence": frozenset({SkillType.GRAMMAR, SkillType.WRITING}),
    "fill_in_the_blank": frozenset(
        {SkillType.GRAMMAR, SkillType.VOCABULARY, SkillType.READING}
    ),
    "multiple_choice": frozenset(
        {SkillType.READING, SkillType.GRAMMAR, SkillType.VOCABULARY}
    ),
    "true_or_false": frozenset({SkillType.READING, SkillType.GRAMMAR}),
    "image_based_choice": frozenset({SkillType.VOCABULARY}),
}

# Used when the lesson label names none of the candidates. Only set where the
# template names its own construct regardless of context; the generic choice
# templates are absent on purpose, so they credit nothing without a label.
DEFAULT_SKILL: dict[str, SkillType] = {
    "short_writing_answer": SkillType.WRITING,
    "translation_choice": SkillType.VOCABULARY,
    "grammar_correction": SkillType.GRAMMAR,
    "arrange_the_sentence": SkillType.GRAMMAR,
    "vocabulary_flashcard": SkillType.VOCABULARY,
    "match_word_to_meaning": SkillType.VOCABULARY,
    "cognitive_fluidity": SkillType.VOCABULARY,
    "collocation_choice": SkillType.VOCABULARY,
    "image_based_choice": SkillType.VOCABULARY,
}


def resolve_exercise_skill(
    ui_type: str | None,
    *,
    has_audio: bool = False,
    lesson_skill: SkillType | None = None,
) -> SkillType | None:
    """The skill one exercise measures, or None when nothing can be said.

    `has_audio` is the discriminator the content itself provides: a gap-fill or
    multiple choice about a recording is listening, the same template without
    audio is not.
    """
    fixed = FIXED_SKILL.get(str(ui_type or ""))
    if fixed:
        return fixed

    candidates = CANDIDATE_SKILLS.get(str(ui_type or ""))
    if candidates is None:
        return None

    if has_audio:
        return SkillType.LISTENING

    if lesson_skill is not None and lesson_skill in candidates:
        return lesson_skill

    return DEFAULT_SKILL.get(str(ui_type or ""))


def attribute_exercises(
    exercises: list[dict],
    outcomes: dict[str, bool],
    *,
    lesson_skill: SkillType | None = None,
) -> dict[SkillType, list[bool]]:
    """Group a lesson's answered exercises by the skill each one measures.

    `outcomes` maps exercise id → whether the learner got it right. Exercises
    the learner did not answer, and exercises no rule can attribute, are left
    out rather than folded into a neighbouring skill.
    """
    by_skill: dict[SkillType, list[bool]] = {}
    for exercise in exercises:
        if not isinstance(exercise, dict):
            continue
        exercise_id = str(exercise.get("id", ""))
        if exercise_id not in outcomes:
            continue
        skill = resolve_exercise_skill(
            exercise.get("ui_type"),
            has_audio=bool(exercise.get("audio_url")),
            lesson_skill=lesson_skill,
        )
        if skill is None:
            continue
        by_skill.setdefault(skill, []).append(outcomes[exercise_id])
    return by_skill
