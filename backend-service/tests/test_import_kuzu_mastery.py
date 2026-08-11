import json
from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock

import pytest
from sqlalchemy.dialects import postgresql

from scripts.import_kuzu_mastery import (
    deterministic_migration_event_id,
    import_page,
    iter_pages,
    load_checkpoint,
    validate_record,
    write_checkpoint,
)


def test_migration_event_id_is_deterministic_and_record_is_validated():
    row = {"schema_version": 1, "user_id": "11111111-1111-1111-1111-111111111111", "concept_id": "c1", "score": 0.7}
    assert deterministic_migration_event_id(row) == deterministic_migration_event_id(row)
    assert len(deterministic_migration_event_id(row)) == 64
    assert validate_record(row)["mastery_probability"] == 0.7


def test_pages_resume_after_durable_checkpoint(tmp_path):
    source = tmp_path / "mastery.jsonl"
    source.write_text("\n".join(json.dumps({"schema_version": 1, "user_id": f"00000000-0000-0000-0000-{i:012d}", "concept_id": "c", "score": 0.5}) for i in range(5)))
    checkpoint = tmp_path / "checkpoint.json"
    write_checkpoint(checkpoint, offset=2, source_sha256="abc")

    pages = list(iter_pages(source, page_size=2, start_offset=load_checkpoint(checkpoint)["offset"]))

    assert [[item["user_id"] for item in page] for page in pages] == [["00000000-0000-0000-0000-000000000002", "00000000-0000-0000-0000-000000000003"], ["00000000-0000-0000-0000-000000000004"]]


@pytest.mark.asyncio
async def test_import_conflict_never_overwrites_newer_online_state():
    session = MagicMock()
    session.scalar = AsyncMock(return_value="migration-event")
    session.execute = AsyncMock(return_value=MagicMock(rowcount=0))
    record = {
        "schema_version": 1,
        "user_id": "11111111-1111-1111-1111-111111111111",
        "concept_id": "c1",
        "score": 0.7,
        "updated_at": datetime(2026, 7, 1, tzinfo=UTC).isoformat(),
    }

    assert await import_page(session, [record]) == (0, 1)

    statement = session.execute.await_args.args[0]
    sql = str(statement.compile(dialect=postgresql.dialect())).lower()
    assert "on conflict" in sql
    assert "do update" in sql
    assert "learner_concept_states.updated_at <= excluded.updated_at" in sql


def test_checkpoint_write_is_atomic_and_replaces_previous_value(tmp_path):
    checkpoint = tmp_path / "checkpoint.json"
    write_checkpoint(checkpoint, offset=2, source_sha256="first")
    write_checkpoint(checkpoint, offset=5, source_sha256="second")

    assert load_checkpoint(checkpoint) == {"offset": 5, "source_sha256": "second"}
    assert not checkpoint.with_suffix(".json.tmp").exists()


def test_malformed_json_is_preserved_as_invalid_record_for_quarantine(tmp_path):
    source = tmp_path / "bad.jsonl"
    source.write_text('{"schema_version": 1}\nnot-json\n')

    page = list(iter_pages(source, page_size=10))[0]

    assert page[1] == {"_invalid_json": "not-json"}
    with pytest.raises((KeyError, ValueError)):
        validate_record(page[1])


@pytest.mark.asyncio
async def test_successful_import_writes_migration_event_and_increments_epoch():
    session = MagicMock()
    session.scalar = AsyncMock(return_value="migration-event")
    session.execute = AsyncMock(return_value=MagicMock(rowcount=1))
    record = {
        "schema_version": 1,
        "user_id": "11111111-1111-1111-1111-111111111111",
        "concept_id": "c1",
        "score": 0.7,
    }

    assert await import_page(session, [record]) == (1, 0)

    event_sql = str(
        session.scalar.await_args.args[0].compile(dialect=postgresql.dialect())
    ).lower()
    executed_sql = [
        str(call.args[0].compile(dialect=postgresql.dialect())).lower()
        for call in session.execute.await_args_list
    ]
    assert "learner_observation_events" in event_sql
    assert deterministic_migration_event_id(record) in event_sql or "event_id" in event_sql
    assert any("learner_state_profiles" in sql and "state_epoch" in sql for sql in executed_sql)
