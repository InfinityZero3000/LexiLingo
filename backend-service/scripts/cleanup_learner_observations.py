"""Bounded learner observation retention cleanup; dry-run by default."""

from __future__ import annotations

import argparse
import asyncio
import json
from dataclasses import asdict
from datetime import UTC, datetime

from app.core.database import AsyncSessionLocal
from app.services.learner_state import cleanup_observation_events


async def run(*, apply: bool, batch_size: int) -> dict:
    async with AsyncSessionLocal() as session:
        result = await cleanup_observation_events(
            session,
            now=datetime.now(UTC),
            dry_run=not apply,
            batch_size=batch_size,
        )
        if apply:
            await session.commit()
        else:
            await session.rollback()
    return {"dry_run": not apply, **asdict(result)}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--batch-size", type=int, default=5000)
    args = parser.parse_args()
    print(json.dumps(asyncio.run(run(apply=args.apply, batch_size=args.batch_size))))


if __name__ == "__main__":
    main()
