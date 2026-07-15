"""Compare a sampled Kuzu export with PostgreSQL learner state without raw IDs."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
from pathlib import Path
from uuid import UUID

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models.learner_state import LearnerConceptState


def hashed_identifier(user_id: str, concept_id: str, salt: str) -> str:
    return hashlib.sha256(f"{salt}|{user_id}|{concept_id}".encode()).hexdigest()[:16]


async def audit(source: Path, *, tolerance: float, sample_size: int, salt: str) -> dict:
    records = []
    with source.open() as handle:
        for line in handle:
            if len(records) >= sample_size:
                break
            records.append(json.loads(line))
    within = missing = divergent = 0
    examples = []
    async with AsyncSessionLocal() as session:
        for item in records:
            row = await session.scalar(
                select(LearnerConceptState).where(
                    LearnerConceptState.user_id == UUID(item["user_id"]),
                    LearnerConceptState.concept_id == item["concept_id"],
                )
            )
            if row is None:
                missing += 1
                continue
            delta = abs(float(row.mastery_probability) - float(item["score"]))
            if delta <= tolerance:
                within += 1
            else:
                divergent += 1
                if len(examples) < 10:
                    examples.append(
                        {
                            "id_hash": hashed_identifier(
                                item["user_id"], item["concept_id"], salt
                            ),
                            "absolute_delta": round(delta, 6),
                        }
                    )
    return {
        "sampled": len(records),
        "within_tolerance": within,
        "missing": missing,
        "divergent": divergent,
        "examples": examples,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--tolerance", type=float, default=0.05)
    parser.add_argument("--sample-size", type=int, default=1000)
    parser.add_argument("--hash-salt", required=True)
    args = parser.parse_args()
    print(
        json.dumps(
            asyncio.run(
                audit(
                    args.source,
                    tolerance=max(0.0, args.tolerance),
                    sample_size=max(1, args.sample_size),
                    salt=args.hash_salt,
                )
            ),
            sort_keys=True,
        )
    )


if __name__ == "__main__":
    main()
