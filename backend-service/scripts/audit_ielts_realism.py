"""
Audit IELTS content against the real exam's form
================================================
The IELTS courses were generated as ordinary app exercises wearing IELTS
titles. This measures the distance between what is stored and what the exam
actually looks like, so the gap is a number rather than an impression.

What it checks, and why each rule exists:

- **A listening question needs a recording.** 52 questions on production say
  "in the lecture…" / "the speaker claims…" while no exercise in the database
  carries an audio field. Nothing plays, so the learner is guessing.
- **True/False is not an IELTS task.** Reading uses TRUE / FALSE / NOT GIVEN
  and YES / NO / NOT GIVEN — three options. A two-option item trains the wrong
  reflex: "not stated" is the option candidates most often miss.
- **IELTS is monolingual.** A matching task pairing English with Vietnamese is
  a vocabulary drill, not an exam task.
- **A completion answer is at most three words.** "NO MORE THAN THREE WORDS" is
  the standard rubric; a sentence-long gap answer cannot be marked.
- **A full mock must be full length.** Listening and Reading are 40 questions.
  A five-question "Full Mock Test" reports a band it cannot support.
- **Every lesson needs a skill label.** Without it the completion is credited
  to vocabulary, which is why listening and writing scores stay near zero.

    venv/bin/python3 scripts/audit_ielts_realism.py
    venv/bin/python3 scripts/audit_ielts_realism.py --course "IELTS Academic"
    venv/bin/python3 scripts/audit_ielts_realism.py --verbose
"""

import argparse
import asyncio
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.core.database import AsyncSessionLocal
from app.models.course import Course, Lesson, Unit

# The task types the real exam uses, per skill.
IELTS_TASKS = {
    "listening": {
        "form_completion", "note_completion", "table_completion",
        "sentence_completion", "multiple_choice", "matching", "map_labelling",
        "plan_labelling", "diagram_labelling", "short_answer",
    },
    "reading": {
        "true_false_notgiven", "yes_no_notgiven", "matching_headings",
        "matching_information", "matching_features", "sentence_completion",
        "summary_completion", "note_completion", "table_completion",
        "diagram_labelling", "multiple_choice", "short_answer",
    },
    "writing": {"task_1", "task_2"},
    "speaking": {"part_1", "part_2", "part_3"},
}

# App ui_types that can stand in for an IELTS task, per skill.
_ACCEPTABLE_UI = {
    "listening": {"listen_and_choose", "dictation", "fill_in_the_blank", "multiple_choice"},
    "reading": {"multiple_choice", "fill_in_the_blank", "categorization",
                "reading_comprehension"},
    "writing": {"short_writing_answer", "grammar_correction"},
    "speaking": {"speaking_repeat", "pronunciation_practice", "short_writing_answer"},
}

_AUDIO_CLAIM = re.compile(
    r"\b(the )?(recording|lecture|conversation|talk|dialogue|audio|passage you hear)\b"
    r"|you (will )?hear\b|the speaker\b|listening passage",
    re.IGNORECASE,
)
_VIETNAMESE = re.compile(r"[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]", re.IGNORECASE)
# Two passes, because an explicit skill word must beat a positional hint. "GT
# Reading Section 1" says Reading; without the precedence it also matches
# "section 1", which is a Listening section, and the ambiguity loses a label
# that the title states outright.
_EXPLICIT = (
    ("listening", ("listening", "listen ", "listen to", "listen for")),
    ("reading", ("reading", "read ", "passage")),
    ("writing", ("writing", "write ", "essay")),
    ("speaking", ("speaking", "speak ", "pronunciation")),
)

_IMPLIED = (
    ("listening", ("section 1", "section 2", "section 3", "section 4", "accents",
                   "lecture", "conversation", "monologue", "note-taking while")),
    ("speaking", ("fluency", "interview", "cue card", "idiomatic language",
                  "word stress", "intonation", "part 1 questions", "part 1 topics",
                  "filler words", "longer answers", "extending answers")),
    ("writing", ("task 1", "task 2", "letter", "bar chart", "line graph",
                 "pie chart", "mixed graph", "double graph", "map description",
                 "process diagram", "describing trends", "cohesion", "coherence",
                 "two-part question")),
    ("reading", ("skimming", "scanning", "not given", "true / false", "true/false",
                 "yes / no", "yes/no", "matching headings", "paragraph headings",
                 "summary & note completion", "diagram & flow chart completion",
                 "advertisement", "short texts", "everyday texts", "academic texts")),
)


def _match(title: str, table) -> str | None:
    matches = {skill for skill, needles in table if any(n in title for n in needles)}
    # A title naming two skills is not a label. Guessing between them would
    # credit the wrong skill silently, which is worse than leaving it blank.
    return matches.pop() if len(matches) == 1 else None


def skill_from_title(title: str) -> str | None:
    """The one skill a lesson title names outright, or None.

    Shared with backfill_content_skill.py — the label that gets written and the
    label the audit expects have to come from the same table.
    """
    lowered = f" {(title or '').lower()} "
    explicit = _match(lowered, _EXPLICIT)
    # "Task 1" and "Task 2" name the Writing paper and nothing else, so a title
    # carrying one alongside a different skill word is describing two things at
    # once — "Task 1: Reading and Understanding Bar Charts" is a Writing lesson
    # that happens to say Reading.
    if explicit and explicit != "writing" and ("task 1" in lowered or "task 2" in lowered):
        return None
    return explicit or _match(lowered, _IMPLIED)


FULL_LENGTH = {"listening": 40, "reading": 40}


def _exercises(lesson: Lesson) -> list[dict]:
    content = lesson.content if isinstance(lesson.content, dict) else {}
    raw = content.get("exercises")
    return [e for e in raw if isinstance(e, dict)] if isinstance(raw, list) else []


def exercise_problems(exercise: dict, skill: str | None, where: str) -> list[str]:
    """Every way one exercise departs from the exam's form.

    Shared with the regenerator, so a replacement is judged by exactly the
    rules that condemned what it replaces.
    """
    problems: list[str] = []
    ui = str(exercise.get("ui_type") or exercise.get("type") or "")
    question = str(exercise.get("question") or "")
    options = exercise.get("options") if isinstance(exercise.get("options"), list) else []
    answer = str(exercise.get("correct_answer") or "")
    has_audio = bool(exercise.get("audio_url") or exercise.get("audio"))

    # dictation and listen_and_choose speak their own text, so they carry their
    # recording by definition; anything else naming one has to have a file.
    speaks_itself = ui in {"dictation", "listen_and_choose", "pronunciation_practice",
                           "speaking_repeat"}
    if _AUDIO_CLAIM.search(question) and not has_audio and not speaks_itself:
        problems.append(f"{where}: asks about a recording that is not attached")

    if ui == "true_or_false":
        problems.append(f"{where}: two-way True/False; the exam uses TRUE/FALSE/NOT GIVEN")

    if _VIETNAMESE.search(question) or any(_VIETNAMESE.search(str(o)) for o in options):
        problems.append(f"{where}: Vietnamese in an IELTS task")
    if _VIETNAMESE.search(answer):
        problems.append(f"{where}: Vietnamese in an IELTS task")

    if ui in {"fill_in_the_blank", "dictation"} and len(answer.split()) > 3:
        problems.append(
            f"{where}: completion answer is {len(answer.split())} words (limit is three)"
        )

    if skill and ui and ui not in _ACCEPTABLE_UI.get(skill, set()):
        problems.append(f"{where}: {ui} is not an IELTS {skill} task")

    return problems


def audit_lesson(lesson: Lesson) -> list[str]:
    """Every way this lesson departs from the exam's form."""
    problems: list[str] = []
    skill = lesson.skill or skill_from_title(lesson.title)
    exercises = _exercises(lesson)

    if not lesson.skill:
        guess = f" (title suggests {skill})" if skill else ""
        problems.append(f"no skill label{guess}")

    title = (lesson.title or "").lower()
    if "mock" in title or "full test" in title:
        expected = FULL_LENGTH.get(skill or "")
        if expected and len(exercises) < expected:
            problems.append(
                f"named a full mock but has {len(exercises)} questions, not {expected}"
            )

    for index, exercise in enumerate(exercises, start=1):
        problems.extend(exercise_problems(exercise, skill, f"Q{index}"))

    return problems


_MOCK_RENAMES = (
    ("full listening mock test", "Listening Practice Set"),
    ("full reading mock test", "Reading Practice Set"),
    ("full speaking mock interview", "Speaking Practice Set"),
    ("gt full mock test simulation", "GT Practice Set"),
    ("full writing mock", "Writing Practice Set"),
    ("mini mock test", "Practice Set"),
    ("mock test", "Practice Set"),
    ("mock interview", "Practice Set"),
    ("full test", "Practice Set"),
)

_MOCK_POINTER = (
    "A full IELTS mock is 40 listening and 40 reading questions and lives in "
    "Practice Tests, not in a lesson. This is a short practice set."
)


def _renamed(title: str) -> str | None:
    """A five-question lesson may not call itself a full mock.

    The real thing exists now — a full-length paper in the IELTS test section —
    so the lesson is renamed to what it is rather than padded out to 40
    questions it was never going to have.
    """
    lowered = (title or "").lower()
    for needle, replacement in _MOCK_RENAMES:
        if needle in lowered:
            start = lowered.index(needle)
            return (title[:start] + replacement + title[start + len(needle):]).strip()
    return None


async def fix_mock_titles(course_filter: str | None, apply: bool) -> int:
    async with AsyncSessionLocal() as db:
        query = select(Course).options(selectinload(Course.units).selectinload(Unit.lessons))
        courses = [
            course
            for course in (await db.execute(query)).scalars().all()
            if "ielts" in (course.title or "").lower()
            and (not course_filter or course_filter.lower() in (course.title or "").lower())
        ]
        changed = 0
        for course in courses:
            for unit in course.units:
                for lesson in unit.lessons:
                    title = lesson.title or ""
                    lowered = title.lower()
                    if "mock" not in lowered and "full test" not in lowered:
                        continue
                    exercises = _exercises(lesson)
                    skill = lesson.skill or skill_from_title(title)
                    expected = FULL_LENGTH.get(skill or "")
                    if expected and len(exercises) >= expected:
                        continue
                    new_title = _renamed(title)
                    if not new_title or new_title == title:
                        continue
                    print(f"  {title!r}\n    -> {new_title!r} ({len(exercises)} questions)")
                    if apply:
                        lesson.title = new_title
                        description = (lesson.description or "").strip()
                        if _MOCK_POINTER not in description:
                            lesson.description = (
                                f"{description} {_MOCK_POINTER}".strip()
                            )
                        changed += 1
        if apply and changed:
            await db.commit()
        print(f"\n{'renamed' if apply else 'would rename'} {changed if apply else '(dry run)'}")
    return 0


async def run(course_filter: str | None, verbose: bool) -> int:
    async with AsyncSessionLocal() as db:
        query = select(Course).options(selectinload(Course.units).selectinload(Unit.lessons))
        courses = (await db.execute(query)).scalars().all()
        courses = [
            c for c in courses
            if "ielts" in (c.title or "").lower()
            and (not course_filter or course_filter.lower() in (c.title or "").lower())
        ]
        if not courses:
            print("No IELTS courses found.")
            return 1

        totals: Counter[str] = Counter()
        for course in sorted(courses, key=lambda c: c.title or ""):
            lessons = sorted(
                (lesson for unit in course.units for lesson in unit.lessons),
                key=lambda l: l.order_index or 0,
            )
            findings = {lesson.title: audit_lesson(lesson) for lesson in lessons}
            clean = sum(1 for problems in findings.values() if not problems)
            count = sum(len(p) for p in findings.values())
            print(
                f"\n{course.title}  [{course.level}]  "
                f"skill={course.skill or '—'}  "
                f"{len(lessons)} lessons, {clean} clean, {count} findings"
            )
            for title, problems in findings.items():
                if not problems:
                    continue
                shown = problems if verbose else problems[:3]
                print(f"  {title}")
                for problem in shown:
                    print(f"    - {problem}")
                if len(problems) > len(shown):
                    print(f"    … {len(problems) - len(shown)} more")
            for problems in findings.values():
                for problem in problems:
                    totals[problem.split(":")[-1].strip()] += 1

        print("\n" + "=" * 70)
        print("Findings by kind")
        for kind, n in totals.most_common():
            print(f"  {n:5d}  {kind}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--course", help="only courses whose title contains this")
    parser.add_argument("--verbose", action="store_true", help="every finding, not the first three")
    parser.add_argument(
        "--fix-mock-titles",
        action="store_true",
        help="rename lessons that call themselves a full mock but are not one",
    )
    parser.add_argument("--apply", action="store_true", help="write the fixes")
    args = parser.parse_args()
    if args.fix_mock_titles:
        return asyncio.run(fix_mock_titles(args.course, args.apply))
    return asyncio.run(run(args.course, args.verbose))


if __name__ == "__main__":
    raise SystemExit(main())
