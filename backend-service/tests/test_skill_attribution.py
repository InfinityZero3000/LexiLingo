"""Which skill an exercise credits, and the refusal to guess when unsure."""

import sys
from pathlib import Path

import pytest

from app.schemas.proficiency import SkillType
from app.services.skill_attribution import (
    attribute_exercises,
    resolve_exercise_skill,
)


@pytest.mark.parametrize(
    ("ui_type", "expected"),
    [
        ("dictation", SkillType.LISTENING),
        ("listen_and_choose", SkillType.LISTENING),
        ("speaking_repeat", SkillType.SPEAKING),
        ("pronunciation_practice", SkillType.SPEAKING),
        ("reading_comprehension", SkillType.READING),
    ],
)
def test_templates_that_settle_their_own_skill(ui_type, expected):
    # Even inside a lesson labelled something else.
    assert (
        resolve_exercise_skill(ui_type, lesson_skill=SkillType.READING) == expected
    )


def test_a_speaking_template_with_audio_is_still_speaking():
    # speaking_repeat carries audio for the learner to imitate; the audio
    # discriminator must not turn it into listening.
    assert (
        resolve_exercise_skill("speaking_repeat", has_audio=True)
        == SkillType.SPEAKING
    )


def test_audio_turns_a_silent_template_into_listening():
    assert resolve_exercise_skill("fill_in_the_blank", has_audio=True) == SkillType.LISTENING
    assert resolve_exercise_skill("multiple_choice", has_audio=True) == SkillType.LISTENING


def test_the_lesson_label_decides_between_plausible_skills():
    assert (
        resolve_exercise_skill("short_writing_answer", lesson_skill=SkillType.SPEAKING)
        == SkillType.SPEAKING
    )
    assert (
        resolve_exercise_skill("short_writing_answer", lesson_skill=SkillType.WRITING)
        == SkillType.WRITING
    )


def test_an_implausible_label_does_not_win():
    # 216 writing exercises sat in lessons labelled `reading`; crediting
    # reading for them is the bug this module exists to fix.
    assert (
        resolve_exercise_skill("short_writing_answer", lesson_skill=SkillType.READING)
        == SkillType.WRITING
    )


def test_generic_choice_templates_credit_nothing_without_a_label():
    # A wrong skill is silent and keeps crediting the wrong pillar; no
    # measurement is the cheaper error.
    assert resolve_exercise_skill("multiple_choice") is None
    assert resolve_exercise_skill("fill_in_the_blank") is None
    assert resolve_exercise_skill("true_or_false") is None


def test_unknown_ui_type_credits_nothing():
    assert resolve_exercise_skill("made_up") is None
    assert resolve_exercise_skill(None) is None


def test_attribution_splits_one_lesson_across_skills():
    exercises = [
        {"id": "1", "ui_type": "multiple_choice"},
        {"id": "2", "ui_type": "dictation"},
        {"id": "3", "ui_type": "short_writing_answer"},
        {"id": "4", "ui_type": "reading_comprehension"},
        {"id": "5", "ui_type": "made_up"},
    ]
    outcomes = {"1": True, "2": False, "3": True, "4": True, "5": True}

    by_skill = attribute_exercises(
        exercises, outcomes, lesson_skill=SkillType.READING
    )

    assert by_skill[SkillType.READING] == [True, True]  # the MCQ and the passage
    assert by_skill[SkillType.LISTENING] == [False]
    assert by_skill[SkillType.WRITING] == [True]
    assert SkillType.VOCABULARY not in by_skill  # the unknown template is dropped


def test_unanswered_exercises_are_not_counted():
    exercises = [
        {"id": "1", "ui_type": "dictation"},
        {"id": "2", "ui_type": "dictation"},
    ]

    by_skill = attribute_exercises(exercises, {"1": True})

    assert by_skill == {SkillType.LISTENING: [True]}


def test_map_agrees_with_the_ielts_audit_table():
    """`scripts/audit_ielts_realism.py` gates what the IELTS regenerator may
    write. If the two disagree, generated content satisfies one and fails the
    other."""
    sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))
    from audit_ielts_realism import _ACCEPTABLE_UI

    for skill_name, ui_types in _ACCEPTABLE_UI.items():
        skill = SkillType(skill_name)
        for ui_type in ui_types:
            resolved = resolve_exercise_skill(
                ui_type,
                has_audio=(skill is SkillType.LISTENING),
                lesson_skill=skill,
            )
            assert resolved == skill, (
                f"{ui_type} in a {skill_name} lesson resolved to {resolved}"
            )
