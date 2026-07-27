"""Offline reverse-sync into a new Kuzu snapshot for late rollback only."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def validate_row(row: dict) -> tuple[str, str, float]:
    user_id = str(row.get("user_id") or "")
    concept_id = str(row.get("concept_id") or "")
    score = float(row["score"])
    if not user_id or not concept_id or not 0 <= score <= 1:
        raise ValueError("invalid reverse-sync row")
    return user_id, concept_id, score


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--target-snapshot", type=Path, required=True)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--confirm-offline-snapshot", action="store_true")
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.apply:
        if not args.confirm_offline_snapshot:
            raise SystemExit("--confirm-offline-snapshot is required with --apply")
        if not args.target_snapshot.exists():
            raise SystemExit("target must be an offline Kuzu topology snapshot")
        if args.manifest is None:
            raise SystemExit("--manifest is required with --apply")
        manifest = json.loads(args.manifest.read_text())
        if manifest.get("schema_version") != 1:
            raise SystemExit("unsupported manifest schema_version")
        if manifest.get("sha256") != sha256_file(args.source):
            raise SystemExit("source checksum does not match manifest")
        with args.source.open() as source_handle:
            record_count = sum(1 for _ in source_handle)
        if int(manifest.get("record_count", -1)) != record_count:
            raise SystemExit("source record count does not match manifest")
    connection = None
    if args.apply:
        import kuzu

        args.target_snapshot.mkdir(parents=True, exist_ok=True)
        connection = kuzu.Connection(kuzu.Database(str(args.target_snapshot)))
    scanned = valid = invalid = applied = missing_concepts = 0
    with args.source.open() as handle:
        for line in handle:
            scanned += 1
            try:
                user_id, concept_id, score = validate_row(json.loads(line))
                valid += 1
                if connection is not None:
                    concept = connection.execute(
                        "MATCH (c:Concept) WHERE c.id=$cid RETURN count(c)",
                        {"cid": concept_id},
                    )
                    if not concept.has_next() or int(concept.get_next()[0]) != 1:
                        missing_concepts += 1
                        continue
                    connection.execute("MERGE (u:User {id: $uid})", {"uid": user_id})
                    connection.execute(
                        "MATCH (u:User), (c:Concept) WHERE u.id=$uid AND c.id=$cid "
                        "MERGE (u)-[m:Mastery]->(c) SET m.score=$score",
                        {"uid": user_id, "cid": concept_id, "score": score},
                    )
                    applied += 1
            except (KeyError, TypeError, ValueError):
                invalid += 1
    if args.apply and (applied != valid or missing_concepts):
        raise SystemExit(
            f"reverse sync incomplete: applied={applied} valid={valid} missing_concepts={missing_concepts}"
        )
    print(json.dumps({"dry_run": not args.apply, "scanned": scanned, "valid": valid, "invalid": invalid, "applied": applied, "missing_concepts": missing_concepts}))


if __name__ == "__main__":
    main()
