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
    venv/bin/python3 scripts/backfill_content_skill.py --from-titles  # add title guesses
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


# The title table lives in audit_ielts_realism, so the label that gets written
# here and the label the audit expects cannot drift apart. Two copies had
# already disagreed on eight lessons.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from audit_ielts_realism import skill_from_title  # noqa: E402


def _lesson_title_guess(lesson: Lesson) -> str | None:
    return skill_from_title(lesson.title)


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


async def backfill(apply: bool, courses_only: bool, from_titles: bool = False) -> int:
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
            def guess_for(lesson: Lesson) -> str | None:
                return _lesson_skill_guess(lesson) or (
                    _lesson_title_guess(lesson) if from_titles else None
                )

            unlabelled = [
                lesson for lesson in lessons if not lesson.skill and guess_for(lesson)
            ]
            source = "audio exercises or a title naming a skill" if from_titles else "audio exercises"
            print(
                f"\nLessons: {len(lessons)} total, "
                f"{len(unlabelled)} with {source} but no skill label"
            )
            for lesson in unlabelled:
                guess = guess_for(lesson)
                print(f"  {lesson.title!r} -> {guess}")
                if apply:
                    lesson.skill = guess
                    lesson_changes += 1

            if from_titles:
                still_blank = [
                    lesson for lesson in lessons if not lesson.skill and not guess_for(lesson)
                ]
                print(
                    f"\n  {len(still_blank)} lesson(s) still unlabelled — their titles "
                    "name no single skill. Label these in the admin dashboard."
                )

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
    parser.add_argument(
        "--from-titles",
        action="store_true",
        help="also label a lesson whose title names exactly one skill",
    )
    args = parser.parse_args()
    return asyncio.run(backfill(args.apply, args.courses_only, args.from_titles))


if __name__ == "__main__":
    raise SystemExit(main())
