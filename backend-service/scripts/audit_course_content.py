"""
Audit Course Content Readiness
==============================
Lists published courses that contain lessons without exercises — those
lessons are unplayable (the learning endpoints reject them with 409) and
are hidden from the roadmap, so the course looks empty or broken in the app.

Run:
    cd backend-service
    venv/bin/python3 scripts/audit_course_content.py
    venv/bin/python3 scripts/audit_course_content.py --unpublish     # demote to draft
    venv/bin/python3 scripts/audit_course_content.py --fix-counters  # repair total_exercises

Fix a reported course by authoring exercises in the admin dashboard or with
`scripts/generate_exercises_ai.py`, then publish it again.
"""

import argparse
import copy
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.crud.course import CourseCRUD
from app.models.course import Course, Lesson


async def fix_counters(db) -> int:
    """Repair Lesson.total_exercises rows written before the model kept it
    in sync with content."""
    result = await db.execute(select(Lesson))
    fixed = 0
    for lesson in result.scalars().all():
        if lesson.total_exercises != lesson.exercise_count:
            lesson.total_exercises = lesson.exercise_count
            fixed += 1
    if fixed:
        await db.commit()
    return fixed


PAIRED_UI_TYPES = {"match_word_to_meaning", "categorization", "cognitive_fluidity"}


def _option_text(option) -> str:
    return option.get("text", "") if isinstance(option, dict) else str(option)


async def fix_matching_options(db) -> int:
    """Rebuild `options` for pair-matching exercises.

    The Flutter widget keeps only each option's text and splits the list in
    half — first half is the left (key) column, second half the right (value)
    column. Content authored as [{id: key, text: value}] therefore rendered
    the values twice and the keys never, making the exercise unanswerable.
    """
    result = await db.execute(select(Lesson))
    fixed = 0
    for lesson in result.scalars().all():
        if not isinstance(lesson.content, dict):
            continue
        # Deep-copy first: mutating the loaded dict in place also mutates the
        # value SQLAlchemy compares against, so the UPDATE is never emitted.
        content = copy.deepcopy(lesson.content)
        changed = False
        for exercise in content.get("exercises") or []:
            if exercise.get("ui_type") not in PAIRED_UI_TYPES:
                continue
            pairs = [
                part.split(":", 1)
                for part in str(exercise.get("correct_answer", "")).split(",")
                if ":" in part
            ]
            if not pairs:
                continue
            wanted = [k.strip() for k, _ in pairs] + [v.strip() for _, v in pairs]
            if [_option_text(o) for o in exercise.get("options") or []] != wanted:
                exercise["options"] = wanted
                changed = True
        if changed:
            # reassign so SQLAlchemy sees the mutation (and re-syncs the counter)
            lesson.content = content
            fixed += 1
    if fixed:
        await db.commit()
    return fixed


async def audit(unpublish: bool, repair_counters: bool, repair_matching: bool = False) -> int:
    async with AsyncSessionLocal() as db:
        if repair_matching:
            print(f"Repaired matching options on {await fix_matching_options(db)} lesson(s).")
        if repair_counters:
            print(f"Repaired total_exercises on {await fix_counters(db)} lesson(s).")

        result = await db.execute(
            select(Course)
            .where(Course.is_published == True)  # noqa: E712
            .order_by(Course.title)
        )
        broken = 0
        for course in result.scalars().all():
            blockers = await CourseCRUD.publish_blockers(db, course.id)
            if not blockers:
                continue
            broken += 1
            print(f"\n[{course.level}] {course.title} ({course.id})")
            for blocker in blockers[:20]:
                print(f"    - {blocker}")
            if len(blockers) > 20:
                print(f"    ... and {len(blockers) - 20} more")
            if unpublish:
                course.is_published = False
                print("  -> unpublished")

        if unpublish and broken:
            await db.commit()

        print(
            f"\n{broken} published course(s) with missing exercises."
            if broken
            else "\nAll published courses are fully playable."
        )
        return broken


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--unpublish",
        action="store_true",
        help="demote every affected course back to draft",
    )
    parser.add_argument(
        "--fix-counters",
        action="store_true",
        help="rewrite stale Lesson.total_exercises values from content",
    )
    parser.add_argument(
        "--fix-matching",
        action="store_true",
        help="rebuild options for pair-matching exercises so both columns render",
    )
    args = parser.parse_args()
    asyncio.run(audit(args.unpublish, args.fix_counters, args.fix_matching))
