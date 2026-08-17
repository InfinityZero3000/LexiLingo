"""
Backfill Course.skill / Lesson.skill
====================================
Courses and lessons authored before the `skill` columns existed have NULL
there, so lesson completion still falls back to guessing the skill from the
course's free-form tags — a guess that lands on "vocabulary" whenever no tag
matches, which is why listening/speaking/reading/writing scores stayed at zero.

This reports what the guess would be for every unlabelled row so you can check
it before writing anything. The 13 large courses only exist in the database
(not reproducible from the repo), so review the report first.

Run:
    cd backend-service
    venv/bin/python3 scripts/backfill_content_skill.py            # report only
    venv/bin/python3 scripts/backfill_content_skill.py --apply    # write the labels
    venv/bin/python3 scripts/backfill_content_skill.py --apply --courses-only
"""

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.course import Course, Lesson
from app.services.proficiency_service import ProficiencyService

# Tags that actually name a skill. `infer_skill_from_tags` answers VOCABULARY
# for anything unmatched, which is fine as a runtime fallback but useless as a
# label: writing it down would turn "we never looked" into "we decided", and a
# four-skill IELTS course would be permanently filed under vocabulary.
_SKILL_TAGS = {
    "grammar",
    "reading",
    "listening",
    "podcast",
    "speaking",
    "pronunciation",
    "conversation",
    "writing",
    "vocabulary",
}


def _flatten_tags(tags) -> list[str]:
    """Course.tags is either a list or a {category: [...]} dict."""
    if isinstance(tags, dict):
        flat: list[str] = []
        for value in tags.values():
            if isinstance(value, list):
                flat.extend(value)
        return flat
    return list(tags) if isinstance(tags, list) else []


def _course_skill_guess(course: Course) -> str | None:
    """The tag-derived skill, or None when no tag names one."""
    flat = _flatten_tags(course.tags)
    if not {str(tag).lower() for tag in flat} & _SKILL_TAGS:
        return None
    return ProficiencyService.infer_skill_from_tags(flat).value


def _lesson_skill_guess(lesson: Lesson) -> str | None:
    """Listening is the one skill a lesson's own content proves: the content
    validator requires an audio_url on listening exercises. Anything else is
    left to the course label rather than guessed per lesson."""
    content = lesson.content if isinstance(lesson.content, dict) else {}
    exercises = content.get("exercises")
    if not isinstance(exercises, list):
        return None
    if any(
        isinstance(exercise, dict) and exercise.get("audio_url")
        for exercise in exercises
    ):
        return "listening"
    return None


async def backfill(apply: bool, courses_only: bool) -> int:
    async with AsyncSessionLocal() as db:
        courses = (await db.execute(select(Course))).scalars().all()
        unlabelled_courses = [c for c in courses if not c.skill]

        print(f"Courses: {len(courses)} total, {len(unlabelled_courses)} unlabelled")
        course_changes = 0
        needs_a_human: list[Course] = []
        for course in unlabelled_courses:
            guess = _course_skill_guess(course)
            if guess is None:
                needs_a_human.append(course)
                continue
            print(f"  [{course.level}] {course.title!r} -> {guess}")
            if apply:
                course.skill = guess
                course_changes += 1

        if needs_a_human:
            print(
                f"\n  {len(needs_a_human)} course(s) have no tag naming a skill. "
                "Left NULL — label these in the admin dashboard:"
            )
            for course in needs_a_human:
                tags = ", ".join(sorted(str(t) for t in _flatten_tags(course.tags))) or "-"
                print(f"    [{course.level}] {course.title!r}  (tags: {tags})")

        lesson_changes = 0
        if not courses_only:
            lessons = (await db.execute(select(Lesson))).scalars().all()
            unlabelled = [
                lesson
                for lesson in lessons
                if not lesson.skill and _lesson_skill_guess(lesson)
            ]
            print(
                f"\nLessons: {len(lessons)} total, "
                f"{len(unlabelled)} with audio exercises but no skill label"
            )
            for lesson in unlabelled:
                guess = _lesson_skill_guess(lesson)
                print(f"  {lesson.title!r} -> {guess}")
                if apply:
                    lesson.skill = guess
                    lesson_changes += 1

        if apply and (course_changes or lesson_changes):
            await db.commit()
            print(
                f"\nWrote {course_changes} course label(s) "
                f"and {lesson_changes} lesson label(s)."
            )
        elif apply:
            print("\nNothing to write.")
        else:
            print("\nReport only — re-run with --apply to write these labels.")

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply", action="store_true", help="write the labels (default: report only)"
    )
    parser.add_argument(
        "--courses-only", action="store_true", help="skip per-lesson labels"
    )
    args = parser.parse_args()
    return asyncio.run(backfill(args.apply, args.courses_only))


if __name__ == "__main__":
    raise SystemExit(main())
