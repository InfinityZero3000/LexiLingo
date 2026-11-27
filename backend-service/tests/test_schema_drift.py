"""The drift check names what production has broken on before, and only reads."""

from sqlalchemy import Column, Enum, MetaData, Table, text

import pytest

from app.services.schema_drift import check_schema_drift
from tests.conftest import _reset_public_schema


@pytest.fixture
async def rebuilt_schema(db_engine):
    """These tests damage the schema on purpose; the shared one is rebuilt for whoever runs next."""
    yield
    await _reset_public_schema(db_engine)


def _kinds(report) -> set[tuple[str, str | None, str]]:
    return {(i["kind"], i["table"], i["detail"]) for i in report["issues"]}


async def test_a_database_built_from_the_models_is_clean(db_engine):
    report = await check_schema_drift(db_engine)

    assert report["ok"] is True and report["issues"] == []


async def test_a_column_the_code_writes_but_the_database_lacks(db_engine, rebuilt_schema):
    async with db_engine.begin() as connection:
        await connection.execute(text("ALTER TABLE exercise_attempts DROP COLUMN attempt_metadata"))

    report = await check_schema_drift(db_engine)

    assert ("missing_column", "exercise_attempts", "attempt_metadata") in _kinds(report)


async def test_a_unique_constraint_an_upsert_relies_on(db_engine, rebuilt_schema):
    async with db_engine.begin() as connection:
        await connection.execute(text("ALTER TABLE vocabulary_items DROP CONSTRAINT uq_vocab_word_pos"))

    report = await check_schema_drift(db_engine)

    assert any(
        kind == "missing_unique" and table == "vocabulary_items" and "uq_vocab_word_pos" in detail
        for kind, table, detail in _kinds(report)
    )


async def test_an_enum_label_the_code_emits_but_the_type_lacks(db_engine):
    async with db_engine.connect() as connection:
        live = (
            await connection.execute(
                text("SELECT t.typname FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid LIMIT 1")
            )
        ).scalar_one()
    wanted = MetaData()
    Table("t", wanted, Column("c", Enum("never_added_label", name=live)))

    report = await check_schema_drift(db_engine, wanted)

    assert ("missing_enum_label", None, f"{live}.never_added_label") in _kinds(report)


async def test_the_ops_endpoint_is_admin_only_and_reports(async_client, auth_headers):
    response = await async_client.get("/api/v1/admin/ops/schema-drift", headers=auth_headers)

    assert response.status_code in (401, 403)


async def test_an_admin_reads_the_report(async_client, super_admin_headers):
    response = await async_client.get("/api/v1/admin/ops/schema-drift", headers=super_admin_headers)

    assert response.status_code == 200
    assert response.json()["ok"] is True
