"""A database built by migrations must accept what the ORM writes."""

from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import text

from app.models.proficiency import SkillType
from app.models.vocabulary import PartOfSpeech

MIGRATION = (
    Path(__file__).resolve().parents[1]
    / "alembic/versions/e9b4c2a7f1d8_align_schema_with_models.py"
)


def _load_migration():
    spec = spec_from_file_location("align_schema_migration", MIGRATION)
    module = module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _upgrade(sync_conn) -> None:
    migration = _load_migration()
    with Operations.context(MigrationContext.configure(sync_conn)):
        migration.upgrade()


async def _labels(conn, type_name: str) -> list[str]:
    rows = await conn.execute(
        text(
            "SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid "
            "WHERE t.typname = :name "
            "AND t.typnamespace = to_regnamespace(current_schema()) "
            "ORDER BY enumsortorder"
        ),
        {"name": type_name},
    )
    return [row[0] for row in rows]


async def test_upgrade_aligns_a_migrated_schema_and_is_repeatable(db_engine):
    async with db_engine.connect() as conn:
        transaction = await conn.begin()
        try:
            await conn.execute(text("CREATE SCHEMA align_check"))
            await conn.execute(text("SET LOCAL search_path TO align_check"))
            for name, enum_cls in (
                ("skilltype", SkillType),
                ("part_of_speech_enum", PartOfSpeech),
            ):
                labels = ", ".join(f"'{member.value}'" for member in enum_cls)
                await conn.execute(text(f"CREATE TYPE {name} AS ENUM ({labels})"))
            await conn.execute(
                text(
                    "CREATE TABLE exercise_attempts (skill skilltype, metadata jsonb)"
                )
            )
            await conn.execute(
                text("INSERT INTO exercise_attempts (skill) VALUES ('grammar')")
            )

            for _ in range(2):
                await conn.run_sync(_upgrade)

            assert await _labels(conn, "skilltype") == [m.name for m in SkillType]
            assert await _labels(conn, "part_of_speech_enum") == [
                m.name for m in PartOfSpeech
            ]
            kept = await conn.execute(
                text("SELECT skill::text, attempt_metadata FROM exercise_attempts")
            )
            assert kept.all() == [("GRAMMAR", None)]
        finally:
            await transaction.rollback()
