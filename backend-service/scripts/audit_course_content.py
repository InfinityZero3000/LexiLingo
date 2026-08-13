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


async def audit(unpublish: bool, repair_counters: bool) -> int:
    async with AsyncSessionLocal() as db:
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
    args = parser.parse_args()
    asyncio.run(audit(args.unpublish, args.fix_counters))
