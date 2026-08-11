"""Export PostgreSQL learner state for a late rollback reverse sync."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
from pathlib import Path

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.learner_state import LearnerConceptState


async def export(output: Path, *, page_size: int = 500) -> int:
    count = 0
    last_id = None
    with output.open("w") as target:
        while True:
            statement = select(LearnerConceptState).order_by(LearnerConceptState.id).limit(page_size)
            if last_id is not None:
                statement = statement.where(LearnerConceptState.id > last_id)
            async with AsyncSessionLocal() as session:
                rows = list((await session.scalars(statement)).all())
            if not rows:
                break
            for row in rows:
                target.write(
                    json.dumps(
                        {
                            "schema_version": 1,
                            "user_id": str(row.user_id),
                            "concept_id": row.concept_id,
                            "score": row.mastery_probability,
                            "updated_at": row.updated_at.isoformat(),
                        },
                        sort_keys=True,
                    )
                    + "\n"
                )
                count += 1
            last_id = rows[-1].id
    output.chmod(0o600)
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--page-size", type=int, default=500)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    count = asyncio.run(export(args.output, page_size=args.page_size))
    checksum = hashlib.sha256()
    with args.output.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            checksum.update(block)
    digest = checksum.hexdigest()
    args.manifest.write_text(
        json.dumps({"schema_version": 1, "record_count": count, "sha256": digest}, sort_keys=True)
        + "\n"
    )
    args.manifest.chmod(0o600)
    print(json.dumps({"exported": count, "sha256": digest}))


if __name__ == "__main__":
    main()
