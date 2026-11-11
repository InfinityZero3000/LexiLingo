"""
Backfill UserProficiencyProfile.placement_level
===============================================
Placement tests taken before the `placement_level` floor existed left no floor
behind, so the learner's next graded exercise recomputed the level from activity
counts alone and erased the result. This restores the floor from each learner's
latest `initial` LevelAssessmentTest.

It writes only `placement_level` / `placement_at`. `assessed_level` and
`users.level` heal on the learner's next graded exercise, which is also when
the rank is recomputed; nothing here touches XP or rank.

Run:
    cd backend-service
    venv/bin/python3 scripts/backfill_placement_level.py           # report only
    venv/bin/python3 scripts/backfill_placement_level.py --apply   # write the floors
"""

import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.proficiency import LevelAssessmentTest, UserProficiencyProfile
from app.schemas.proficiency import ProficiencyLevel
from app.services.proficiency_service import ProficiencyService


def _index(level: str) -> int:
    return ProficiencyService.get_level_index(ProficiencyLevel(level))


async def main(apply: bool) -> None:
    async with AsyncSessionLocal() as db:
        profiles = (
            (
                await db.execute(
                    select(UserProficiencyProfile).where(
                        UserProficiencyProfile.placement_level.is_(None)
                    )
                )
            )
            .scalars()
            .all()
        )

        restored = erased = 0
        for profile in profiles:
            test = (
                await db.execute(
                    select(LevelAssessmentTest)
                    .where(
                        LevelAssessmentTest.user_id == profile.user_id,
                        LevelAssessmentTest.test_type == "initial",
                        LevelAssessmentTest.assessed_level.is_not(None),
                    )
                    .order_by(LevelAssessmentTest.completed_at.desc())
                    .limit(1)
                )
            ).scalar_one_or_none()
            if test is None or test.assessed_level not in ProficiencyLevel._value2member_map_:
                continue

            below = _index(profile.assessed_level) < _index(test.assessed_level)
            erased += below
            restored += 1
            print(
                f"{profile.user_id}  placed {test.assessed_level}  now {profile.assessed_level}"
                f"{'  <- erased by later activity' if below else ''}"
            )
            if apply:
                profile.placement_level = test.assessed_level
                profile.placement_at = test.completed_at

        if apply:
            await db.commit()

        print(
            f"\n{len(profiles)} profiles without a floor, {restored} with an initial test "
            f"({erased} currently below it). {'Written.' if apply else 'Report only; pass --apply.'}"
        )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    asyncio.run(main(parser.parse_args().apply))
