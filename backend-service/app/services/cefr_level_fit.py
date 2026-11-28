"""Does a course's text sit at the CEFR level it declares?

Nothing used to check this: the C2 course was 79% A1/A2 vocabulary and the A1
IELTS Foundation course had 28.5% of its content words above A1. Everything
here is report-only; no publish gate reads it yet.

Words are measured against a lexicon (word -> lowest CEFR level it is listed
at). Words the lexicon does not list are counted separately and never held
against a course, so a thin lexicon makes verdicts "unknown", not wrong.
"""

from __future__ import annotations

import re
from collections import Counter
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

from app.core.free_form_writing import is_vietnamese

LEVELS: tuple[str, ...] = ("A1", "A2", "B1", "B2", "C1", "C2")
_RANK = {level: index for index, level in enumerate(LEVELS)}

# Below this many listed content words a share is noise, so no verdict.
MIN_LISTED_WORDS = 30

# Fraction of listed words above the declared level that makes a course too
# hard. Real A1 courses carry some stretch vocabulary and the lexicon lists
# many everyday words at A2 or B1, so 15% leaves room; the audited A1 course
# at 28.5% is well past it.
TOO_HARD_ABOVE_SHARE = 0.15

# From B2 up, a course should lean on words at or just below its level. If
# fewer than this share of listed words sit at declared-1 or higher, the
# course is teaching its level's label with lower-level words (the C2 course
# measured ~2%). Below B2 the lexicon has no useful "too easy": beginners
# legitimately repeat A1 words.
TOO_EASY_MIN_NEAR_SHARE = 0.10
TOO_EASY_FROM_LEVEL = "B2"

_STOPWORDS = frozenset(
    """
    the and for are but not you all any can had her was one our out has him his how
    its let may new now old see two way who did get got she too use been does done
    from have here just like more much must only over such than that their them then
    there these they this very what when where which while will with would your about
    after also because before being both each into other some should could were those
    through under until upon whom whose yours mine ours
    """.split()
)

_CONTRACTION = re.compile(r"(n't|'s|'re|'ll|'ve|'d|'m)\b")
_WORD = re.compile(r"[a-z]+")
_SEGMENT_SPLIT = re.compile(r"[:;,.!?\"“”()\[\]\n]|(?<![A-Za-z])['‘’]|['‘’](?![A-Za-z])|\s[-–—]\s|\{blank\}|_+")
_VOWELS = "aeiou"


def tokenize(text: str) -> list[str]:
    """Lowercase English content words; Vietnamese segments are dropped first,
    because help text and glosses are written for the learner, not tested on."""
    kept = [
        segment
        for segment in _SEGMENT_SPLIT.split(str(text or ""))
        if segment and not is_vietnamese(segment)
    ]
    cleaned = _CONTRACTION.sub("", " ".join(kept).lower().replace("’", "'"))
    return [
        word
        for word in _WORD.findall(cleaned)
        if len(word) >= 3 and word not in _STOPWORDS
    ]


def _candidates(word: str) -> Iterable[str]:
    """Plausible base forms, most specific first. Not a real lemmatizer: it
    only has to land on a listed word often enough to measure a course."""
    yield word
    for suffix, replacements in (
        ("ies", ("y",)),
        ("ied", ("y",)),
        ("ier", ("y",)),
        ("iest", ("y",)),
        ("es", ("", "e")),
        ("s", ("",)),
        ("ing", ("", "e")),
        ("ed", ("", "e")),
        ("ly", ("", "le")),
        ("er", ("", "e")),
        ("est", ("", "e")),
    ):
        if word.endswith(suffix) and len(word) - len(suffix) >= 3:
            stem = word[: -len(suffix)]
            for replacement in replacements:
                yield stem + replacement
            if (
                suffix in ("ing", "ed", "er", "est")
                and len(stem) >= 4
                and stem[-1] == stem[-2]
                and stem[-1] not in _VOWELS
            ):
                yield stem[:-1]


def lookup(word: str, lexicon: Mapping[str, str]) -> str | None:
    for candidate in _candidates(word):
        level = lexicon.get(candidate)
        if level:
            return level
    return None


def level_profile(texts: Iterable[str], lexicon: Mapping[str, str]) -> dict[str, Any]:
    """Counts of content-word occurrences per CEFR level.

    `n` is every content word, `listed` the ones the lexicon placed.
    """
    counts: Counter[str] = Counter()
    unlisted = 0
    for text in texts:
        for word in tokenize(text):
            level = lookup(word, lexicon)
            if level in _RANK:
                counts[level] += 1
            else:
                unlisted += 1
    listed = sum(counts.values())
    return {
        "counts": {level: counts[level] for level in LEVELS},
        "listed": listed,
        "unlisted": unlisted,
        "n": listed + unlisted,
    }


def share_above(profile: Mapping[str, Any], level: str, *, inclusive: bool = False) -> float:
    """Share of listed words above `level` (or at it too when `inclusive`)."""
    listed = profile["listed"]
    if not listed:
        return 0.0
    floor = _RANK[level] + (0 if inclusive else 1)
    return sum(profile["counts"][name] for name in LEVELS[floor:]) / listed


def level_fit(profile: Mapping[str, Any], declared: str | None) -> dict[str, Any]:
    declared = (declared or "").upper()
    result: dict[str, Any] = {
        "declared": declared or None,
        "listed": profile["listed"],
        "above_share": None,
        "near_or_above_share": None,
        "verdict": "unknown",
    }
    if declared not in _RANK or profile["listed"] < MIN_LISTED_WORDS:
        return result
    near = LEVELS[max(_RANK[declared] - 1, 0)]
    above = share_above(profile, declared)
    near_or_above = share_above(profile, near, inclusive=True)
    result["above_share"] = round(above, 4)
    result["near_or_above_share"] = round(near_or_above, 4)
    if above > TOO_HARD_ABOVE_SHARE:
        result["verdict"] = "too_hard"
    elif (
        _RANK[declared] >= _RANK[TOO_EASY_FROM_LEVEL]
        and near_or_above < TOO_EASY_MIN_NEAR_SHARE
    ):
        result["verdict"] = "too_easy"
    else:
        result["verdict"] = "fits"
    return result


def lesson_texts(lesson: Mapping[str, Any]) -> list[str]:
    """Learner-facing English in a lesson: prompts (reading passages ride in
    `question`), options, answers. `explanation` is help text and is skipped."""
    texts: list[str] = []
    for exercise in lesson.get("exercises") or []:
        if not isinstance(exercise, dict):
            continue
        texts.append(str(exercise.get("question") or ""))
        for option in exercise.get("options") or []:
            texts.append(str(option.get("text", "")) if isinstance(option, dict) else str(option))
        texts.append(str(exercise.get("correct_answer") or ""))
    return texts


def course_level_fit(course: Mapping[str, Any], lexicon: Mapping[str, str]) -> dict[str, Any]:
    """Course-wide fit plus each lesson's, worst (highest above_share) first."""
    all_texts: list[str] = []
    lessons: list[dict[str, Any]] = []
    for lesson in course["lessons"]:
        texts = lesson_texts(lesson)
        all_texts.extend(texts)
        profile = level_profile(texts, lexicon)
        above = share_above(profile, course["level"]) if profile["listed"] else 0.0
        lessons.append(
            {
                "title": lesson.get("title"),
                "listed": profile["listed"],
                "above_share": round(above, 4),
            }
        )
    profile = level_profile(all_texts, lexicon)
    worst = sorted(
        (item for item in lessons if item["listed"] >= 10),
        key=lambda item: item["above_share"],
        reverse=True,
    )[:3]
    return {**level_fit(profile, course["level"]), "profile": profile, "worst_lessons": worst}


def course_view(course: Any) -> dict[str, Any]:
    """Plain-dict view of a Course ORM row with `units.lessons` loaded."""
    lessons = []
    for unit in sorted(course.units, key=lambda unit: unit.order_index):
        for lesson in sorted(unit.lessons, key=lambda lesson: lesson.order_index):
            content = lesson.content if isinstance(lesson.content, dict) else {}
            lessons.append(
                {
                    "unit": unit.title,
                    "title": lesson.title,
                    "outcome": lesson.outcome,
                    "skill": lesson.skill,
                    "exercises": content.get("exercises") or [],
                }
            )
    return {"title": course.title, "level": course.level, "skill": course.skill, "lessons": lessons}


def course_view_from_export(data: Mapping[str, Any]) -> dict[str, Any]:
    """The same view from a committed `content/courses/*.json` export."""
    units = {unit["id"]: unit for unit in data.get("units") or []}
    ordered = sorted(
        data.get("lessons") or [],
        key=lambda lesson: (
            units.get(lesson.get("unit_id"), {}).get("order_index", 0),
            lesson.get("order_index", 0),
        ),
    )
    course = data["course"]
    return {
        "title": course["title"],
        "level": course["level"],
        "skill": course.get("skill"),
        "lessons": [
            {
                "unit": units.get(lesson.get("unit_id"), {}).get("title"),
                "title": lesson.get("title"),
                "outcome": lesson.get("outcome"),
                "skill": lesson.get("skill"),
                "exercises": (lesson.get("content") or {}).get("exercises") or [],
            }
            for lesson in ordered
        ],
    }


def course_balance(course: Mapping[str, Any]) -> dict[str, Any]:
    """Which skills a course measures, where it never asks for production, and
    whether lessons carry can-do outcomes. Takes the `course_view` shape."""
    from app.services.exercise_generation import is_production
    from app.services.skill_attribution import resolve_exercise_skill

    skills: Counter[str] = Counter()
    unattributed = 0
    unit_production: dict[str, bool] = {}
    with_outcome = can_do = 0
    lessons = course["lessons"]
    for lesson in lessons:
        outcome = str(lesson.get("outcome") or "").strip()
        with_outcome += bool(outcome)
        can_do += outcome.lower().startswith(("you can", "i can"))
        unit = lesson.get("unit") or ""
        unit_production.setdefault(unit, False)
        for exercise in lesson["exercises"]:
            if not isinstance(exercise, dict) or "ui_type" not in exercise:
                continue
            skill = resolve_exercise_skill(
                exercise["ui_type"], has_audio=bool(exercise.get("audio_url"))
            )
            if skill is None:
                unattributed += 1
            else:
                skills[skill.value] += 1
            if is_production(exercise):
                unit_production[unit] = True

    declared = (course.get("skill") or "").lower() or None
    dominant = skills.most_common(1)[0][0] if skills else None
    count = len(lessons)
    return {
        "lessons": count,
        "skills": dict(skills),
        "unattributed": unattributed,
        "dominant_skill": dominant,
        "declared_skill": declared,
        "declared_skill_exercises": skills.get(declared, 0) if declared else None,
        "skill_mismatch": bool(declared and dominant and declared != dominant),
        "units_without_production": [unit for unit, has in unit_production.items() if not has],
        "outcome_share": round(with_outcome / count, 4) if count else 0.0,
        "can_do_outcomes": can_do,
    }


def load_lexicon_file(path: str | Path) -> dict[str, str]:
    """Lowest level per spelling from `ai-service/data/lexicon/cefr_vocabulary.jsonl`.

    The CEFR-J rows carry a commercial licence: use for measurement only, never
    copy into this service or return it in a response.
    """
    import json

    lexicon: dict[str, str] = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            row = json.loads(line)
            level = str(row.get("cefr") or "").upper()
            if level not in _RANK:
                continue
            for spelling in {row.get("word"), *(row.get("variants") or [])}:
                _keep_lowest(lexicon, spelling, level)
    return lexicon


def _keep_lowest(lexicon: dict[str, str], spelling: Any, level: str) -> None:
    word = str(spelling or "").strip().lower()
    if not word or not word.isalpha():
        return
    current = lexicon.get(word)
    if current is None or _RANK[level] < _RANK[current]:
        lexicon[word] = level


async def load_lexicon(db: Any) -> dict[str, str]:
    """word -> lowest `VocabularyItem.difficulty_level` in the database."""
    from sqlalchemy import select

    from app.models.vocabulary import VocabularyItem

    lexicon: dict[str, str] = {}
    result = await db.execute(select(VocabularyItem.word, VocabularyItem.difficulty_level))
    for word, level in result.all():
        name = getattr(level, "value", level)
        if name:
            _keep_lowest(lexicon, word, str(name).upper())
    return lexicon


def format_row(title: str, fit: Mapping[str, Any]) -> str:
    """One markdown table row: declared, % of listed words per level, verdict, worst lessons."""
    profile = fit["profile"]
    listed = profile["listed"] or 1
    shares = " ".join(f"{profile['counts'][level] * 100 / listed:.0f}" for level in LEVELS)
    above = "-" if fit["above_share"] is None else f"{fit['above_share'] * 100:.1f}%"
    worst = "; ".join(f"{item['title']} ({item['above_share'] * 100:.0f}%)" for item in fit["worst_lessons"])
    return (
        f"| {title} | {fit['declared']} | {shares} | {profile['unlisted'] * 100 // max(profile['n'], 1)}% "
        f"| {above} | {fit['verdict']} | {worst} |"
    )


TABLE_HEADER = (
    "| Course | Declared | A1 A2 B1 B2 C1 C2 (% of listed) | Unlisted | Above declared | Verdict | Worst lessons (% above) |\n"
    "|---|---|---|---|---|---|---|"
)


async def load_course_views(db: Any, course_id: Any = None) -> list[dict[str, Any]]:
    """`course_view`s for one course, or for every published course by title."""
    from sqlalchemy import select
    from sqlalchemy.orm import selectinload

    from app.models.course import Course, Unit

    query = select(Course).options(selectinload(Course.units).selectinload(Unit.lessons))
    query = query.where(Course.id == course_id) if course_id else query.where(Course.is_published.is_(True))
    result = await db.execute(query.order_by(Course.title))
    return [course_view(course) for course in result.scalars().all()]
