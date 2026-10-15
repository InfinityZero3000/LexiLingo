"""Seed the full-length IELTS Academic practice paper.

The paper itself lives in `scripts/ielts_paper_academic_1.py`; this only writes
it to the database. Idempotent by title, so re-running it updates the content
of the existing row rather than creating a second copy.

It lands the test **unpublished** when the paper does not yet pass the admin
publish gate — which today means the Listening recordings, since a Listening
part with no `audio_url` is a section nobody can answer.

    venv/bin/python3 scripts/seed_ielts_test.py
    venv/bin/python3 scripts/seed_ielts_test.py --publish   # override the gate
"""

import argparse
import asyncio
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.ielts import IeltsTest
from app.routes.admin_ielts import validate_test_content
from app.services.ielts_service import iter_questions

from ielts_paper_academic_1 import CONTENT, DESCRIPTION, SLUG, TITLE


def _carry_over_audio(previous: dict | None) -> dict:
    """Keep recordings that have already been attached.

    The paper in the repo has empty `audio_url` fields, so re-seeding would
    otherwise silence a Listening section that someone had uploaded audio for.
    """
    if not isinstance(previous, dict):
        return CONTENT
    known = {
        part.get("part_key"): part.get("audio_url")
        for section in previous.get("sections") or []
        if (section.get("skill") or "").lower() == "listening"
        for part in section.get("parts") or []
        if isinstance(part, dict) and part.get("audio_url")
    }
    if not known:
        return CONTENT
    content = copy.deepcopy(CONTENT)
    for section in content["sections"]:
        if section["skill"] != "listening":
            continue
        for part in section["parts"]:
            if known.get(part.get("part_key")):
                part["audio_url"] = known[part["part_key"]]
    return content


async def main(force_publish: bool) -> int:
    async with AsyncSessionLocal() as db:
        existing = await db.execute(select(IeltsTest).where(IeltsTest.title == TITLE))
        test = existing.scalar_one_or_none()
        content = _carry_over_audio(test.content if test else None)
        problems = validate_test_content(content, skill_scope="full")
        blocking = [p for p in problems if "audio_url" not in p]
        publishable = force_publish or not problems
        if test:
            test.content = content
            test.description = DESCRIPTION
            # Demote deliberately: a published paper whose Listening cannot be
            # heard is a section nobody can answer.
            test.is_published = publishable
            action = "updated"
        else:
            test = IeltsTest(
                title=TITLE,
                description=DESCRIPTION,
                test_type="academic",
                skill_scope="full",
                target_band="6.0-7.5",
                slug=SLUG,
                content=content,
                is_published=publishable,
            )
            db.add(test)
            action = "created"
        await db.commit()
        await db.refresh(test)
        test_id, published = test.id, test.is_published

    counts = {
        skill: len(list(iter_questions(content, skill)))
        for skill in ("listening", "reading")
    }
    print(f"{action}: {TITLE} ({test_id})")
    print(f"  listening {counts['listening']} questions, reading {counts['reading']} questions")
    print("  writing 2 tasks, speaking 3 parts")
    print(f"  published: {published}")

    if problems:
        print(f"\n  {len(problems)} problem(s) block publishing:")
        for problem in problems:
            print(f"    - {problem}")
        if not blocking:
            print(
                "\n  All of them are missing recordings. Every Listening part carries "
                "its transcript, so the recordings can be produced from the text and "
                "uploaded in the admin IELTS page."
            )
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--publish",
        action="store_true",
        help="publish even though the paper does not pass the gate",
    )
    args = parser.parse_args()
    raise SystemExit(asyncio.run(main(args.publish)))
