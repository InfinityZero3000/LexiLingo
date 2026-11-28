"""Blind second pass over generated choice questions: the model answers each one
without the key or the explanation, and only agreeing exercises survive."""

from __future__ import annotations

import json
import logging
from collections.abc import Awaitable, Callable

from api.models.content_agent import ExerciseArtifact

logger = logging.getLogger(__name__)

METHOD = "blind-answer-v1"

# Free-form and similarity-graded answers have no single option to pick, pair and
# arrange types have no option that is "the answer", and a listen_and_choose key
# is whatever the app speaks aloud, so a model that cannot hear it can only guess.
UNVERIFIABLE_UI_TYPES: frozenset[str] = frozenset(
    {
        "short_writing_answer",
        "speaking_repeat",
        "pronunciation_practice",
        "arrange_the_sentence",
        "listen_and_choose",
        "match_word_to_meaning",
        "categorization",
        "cognitive_fluidity",
    }
)


class VerificationUnavailable(RuntimeError):
    """The blind pass could not be completed, so no key was checked."""


def is_verifiable(exercise: ExerciseArtifact) -> bool:
    return exercise.ui_type not in UNVERIFIABLE_UI_TYPES and len(exercise.options or []) >= 2


def _norm(value: object) -> str:
    return " ".join(str(value).strip().lower().split())


def verification_prompt(level: str, lesson_title: str, items: list[ExerciseArtifact]) -> str:
    lines = [
        json.dumps({"n": n, "question": item.question, "options": item.options}, ensure_ascii=False)
        for n, item in enumerate(items)
    ]
    return (
        f"You are checking quiz questions for an English course (level {level}, lesson "
        f"'{lesson_title}'). Answer each question yourself; nothing tells you which option the "
        "author intended, so decide from the language alone. A True/False question is about "
        "whether the statement is true.\n\nQUESTIONS (one JSON object per line):\n"
        + "\n".join(lines)
        + "\n\nFor each question give the 0-based index of the single correct option, or -1 if "
        "no option is correct or more than one is.\n"
        'Return {"answers":[{"n":<n>,"index":<index>}]}'
    )


async def verify_exercises(
    exercises: list[ExerciseArtifact],
    *,
    level: str,
    lesson_title: str,
    call: Callable[[str], Awaitable[dict]],
) -> tuple[list[ExerciseArtifact], dict]:
    """Returns the surviving exercises and the stats. Raises VerificationUnavailable
    when the pass fails twice: an unchecked key must never be passed off as checked."""
    checked = [exercise for exercise in exercises if is_verifiable(exercise)]
    stats: dict = {"method": METHOD, "checked": len(checked), "agreed": 0, "dropped": []}
    if not checked:
        return list(exercises), stats

    prompt = verification_prompt(level, lesson_title, checked)
    picks: dict[int, int] = {}
    for attempt in range(2):
        try:
            reply = await call(prompt)
            answers = reply.get("answers") if isinstance(reply, dict) else None
            if not isinstance(answers, list):
                raise ValueError("no answers list")
            picks = {
                a["n"]: a["index"]
                for a in answers
                if isinstance(a, dict) and isinstance(a.get("n"), int) and isinstance(a.get("index"), int)
            }
            break
        except Exception as exc:
            logger.warning("answer-key verification failed (attempt %d): %s", attempt + 1, exc)
    else:
        raise VerificationUnavailable("blind answer pass failed twice")

    dropped: set[int] = set()
    for n, item in enumerate(checked):
        index = picks.get(n)
        options = item.options or []
        if index is not None and 0 <= index < len(options) and _norm(options[index]) == _norm(item.correct_answer):
            stats["agreed"] += 1
        else:
            dropped.add(id(item))
            stats["dropped"].append(item.id)
    return [exercise for exercise in exercises if id(exercise) not in dropped], stats
