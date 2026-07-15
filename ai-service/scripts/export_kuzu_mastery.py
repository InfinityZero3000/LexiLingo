"""Export learner mastery from a read-only Kuzu snapshot to versioned JSONL."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterable


def export_rows(
    rows: Iterable[dict], *, output: Path, manifest: Path, page_size: int = 500
) -> dict:
    del page_size  # the source iterator owns paging; rows are never materialized here
    digest = hashlib.sha256()
    count = 0
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("wb") as target:
        for raw in rows:
            record = {
                "schema_version": 1,
                "user_id": str(raw["user_id"]),
                "concept_id": str(raw["concept_id"]),
                "score": float(raw["score"]),
                "updated_at": raw.get("updated_at"),
            }
            encoded = (json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n").encode()
            target.write(encoded)
            digest.update(encoded)
            count += 1
    output.chmod(0o600)
    result = {
        "schema_version": 1,
        "record_count": count,
        "sha256": digest.hexdigest(),
        "created_at": datetime.now(UTC).isoformat(),
    }
    manifest.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    manifest.chmod(0o600)
    return {"exported": count, **result}


def iter_kuzu_rows(snapshot: Path):
    import kuzu

    database = kuzu.Database(str(snapshot), read_only=True)
    connection = kuzu.Connection(database)
    result = connection.execute(
        "MATCH (u:User)-[m:Mastery]->(c:Concept) "
        "RETURN u.id, c.id, m.score ORDER BY u.id, c.id"
    )
    while result.has_next():
        user_id, concept_id, score = result.get_next()
        yield {"user_id": user_id, "concept_id": concept_id, "score": score}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--page-size", type=int, default=500)
    args = parser.parse_args()
    if not args.snapshot.exists():
        raise SystemExit("snapshot path does not exist")
    result = export_rows(
        iter_kuzu_rows(args.snapshot),
        output=args.output,
        manifest=args.manifest,
        page_size=max(1, args.page_size),
    )
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
