"""Resumable, dry-run-by-default importer for a Kuzu mastery JSONL export."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
from collections.abc import Iterator
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4


def deterministic_migration_event_id(record: dict) -> str:
    material = f"kuzu-migration-v1|{record['user_id']}|{record['concept_id']}"
    return hashlib.sha256(material.encode()).hexdigest()


def validate_record(record: dict) -> dict:
    if record.get("schema_version") != 1:
        raise ValueError("unsupported schema_version")
    user_id = str(record.get("user_id") or "")
    concept_id = str(record.get("concept_id") or "")
    score = float(record["score"])
    if not user_id or not concept_id or len(concept_id) > 255 or not 0 <= score <= 1:
        raise ValueError("invalid mastery record")
    return {
        "user_id": UUID(user_id),
        "concept_id": concept_id,
        "mastery_probability": score,
        "updated_at": record.get("updated_at"),
        "event_id": deterministic_migration_event_id(record),
    }


async def import_page(session, records: list[dict]) -> tuple[int, int]:
    """Insert migration state without overwriting a newer online state."""
    from sqlalchemy.dialects.postgresql import insert as pg_insert

    from app.models.learner_state import (
        LearnerConceptState,
        LearnerObservationEvent,
        LearnerStateProfile,
    )

    inserted = skipped = 0
    for raw in records:
        item = validate_record(raw)
        source_updated = item["updated_at"]
        if isinstance(source_updated, str):
            source_updated = datetime.fromisoformat(source_updated.replace("Z", "+00:00"))
        values = {
            "id": uuid4(),
            "user_id": item["user_id"],
            "concept_id": item["concept_id"],
            "mastery_probability": item["mastery_probability"],
            "algorithm_version": "kuzu-migration-v1",
            "updated_at": source_updated or datetime.now(UTC),
        }
        migration_event = (
            pg_insert(LearnerObservationEvent)
            .values(
                id=uuid4(),
                event_id=item["event_id"],
                user_id=item["user_id"],
                concept_id=item["concept_id"],
                outcome="correct",
                confidence=1.0,
                observed_at=source_updated or datetime.now(UTC),
                payload={"source": "kuzu", "migration_version": 1},
                status="applied",
                applied_at=datetime.now(UTC),
                available_at=datetime.now(UTC),
            )
            .on_conflict_do_nothing(index_elements=["event_id"])
            .returning(LearnerObservationEvent.event_id)
        )
        if (await session.scalar(migration_event)) is None:
            skipped += 1
            continue
        statement = pg_insert(LearnerConceptState).values(**values)
        if source_updated is None:
            statement = statement.on_conflict_do_nothing(
                index_elements=["user_id", "concept_id"]
            )
        else:
            statement = statement.on_conflict_do_update(
                index_elements=["user_id", "concept_id"],
                set_={
                    "mastery_probability": statement.excluded.mastery_probability,
                    "algorithm_version": statement.excluded.algorithm_version,
                    "updated_at": statement.excluded.updated_at,
                },
                where=LearnerConceptState.updated_at <= statement.excluded.updated_at,
            )
        result = await session.execute(statement)
        if result.rowcount:
            inserted += 1
            await session.execute(
                pg_insert(LearnerStateProfile)
                .values(user_id=item["user_id"], state_epoch=1, updated_at=datetime.now(UTC))
                .on_conflict_do_update(
                    index_elements=["user_id"],
                    set_={
                        "state_epoch": LearnerStateProfile.state_epoch + 1,
                        "updated_at": datetime.now(UTC),
                    },
                )
            )
        else:
            skipped += 1
    return inserted, skipped


def iter_pages(source: Path, *, page_size: int, start_offset: int = 0) -> Iterator[list[dict]]:
    page: list[dict] = []
    with source.open() as handle:
        for offset, line in enumerate(handle):
            if offset < start_offset:
                continue
            try:
                page.append(json.loads(line))
            except json.JSONDecodeError:
                page.append({"_invalid_json": line.rstrip("\n")})
            if len(page) >= max(1, page_size):
                yield page
                page = []
    if page:
        yield page


def load_checkpoint(path: Path) -> dict:
    if not path.exists():
        return {"offset": 0, "source_sha256": None}
    return json.loads(path.read_text())


def write_checkpoint(path: Path, *, offset: int, source_sha256: str) -> None:
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(
        json.dumps({"offset": offset, "source_sha256": source_sha256}, sort_keys=True)
    )
    temporary.chmod(0o600)
    temporary.replace(path)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


async def async_main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--checkpoint", type=Path, required=True)
    parser.add_argument("--page-size", type=int, default=500)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--quarantine", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    digest = file_sha256(args.source)
    if args.apply:
        if args.manifest is None:
            raise SystemExit("--manifest is required with --apply")
        manifest = json.loads(args.manifest.read_text())
        if manifest.get("sha256") != digest:
            raise SystemExit("source checksum does not match manifest")
        with args.source.open() as source_handle:
            record_count = sum(1 for _ in source_handle)
        if int(manifest.get("record_count", -1)) != record_count:
            raise SystemExit("source record count does not match manifest")
    checkpoint = load_checkpoint(args.checkpoint)
    if checkpoint["source_sha256"] not in (None, digest):
        raise SystemExit("checkpoint belongs to a different source")
    scanned = valid = invalid = inserted = skipped_newer = 0
    offset = int(checkpoint["offset"])
    if args.apply:
        from app.core.database import AsyncSessionLocal
    for page in iter_pages(args.source, page_size=args.page_size, start_offset=offset):
        scanned += len(page)
        valid_records = []
        for record in page:
            try:
                validate_record(record)
                valid += 1
                valid_records.append(record)
            except (KeyError, TypeError, ValueError):
                invalid += 1
                if args.quarantine:
                    with args.quarantine.open("a") as target:
                        target.write(json.dumps(record, sort_keys=True) + "\n")
                    args.quarantine.chmod(0o600)
        offset += len(page)
        if args.apply:
            async with AsyncSessionLocal() as session:
                page_inserted, page_skipped = await import_page(session, valid_records)
                await session.commit()
            inserted += page_inserted
            skipped_newer += page_skipped
            write_checkpoint(args.checkpoint, offset=offset, source_sha256=digest)
    print(json.dumps({"dry_run": not args.apply, "scanned": scanned, "valid": valid, "invalid": invalid, "inserted": inserted, "skipped_newer": skipped_newer}))


def main() -> None:
    asyncio.run(async_main())


if __name__ == "__main__":
    main()
