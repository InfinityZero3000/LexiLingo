"""Where the live database has fallen behind the models.

Each kind here broke production once: a column the code writes but no migration
added (`exercise_attempts.attempt_metadata`), an enum label the code emits that
the type never got, and a unique constraint that `ON CONFLICT` or an upsert names
(`uq_vocab_word_pos`) but the database lacks, which fails only when the statement runs.

Read-only. It reports; it never alters anything and never raises to its caller.
"""

from datetime import datetime, timezone
from typing import Any

from sqlalchemy import Enum, MetaData, inspect, text
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import AsyncEngine

from app.core.database import Base

Issue = dict[str, Any]


def _model_enums(metadata: MetaData) -> dict[str, set[str]]:
    wanted: dict[str, set[str]] = {}
    for table in metadata.tables.values():
        for column in table.columns:
            kind = column.type
            if isinstance(kind, Enum) and kind.native_enum and kind.name:
                wanted.setdefault(kind.name, set()).update(kind.enums)
    return wanted


def _live_enums(connection: Connection) -> dict[str, set[str]]:
    rows = connection.execute(
        text("SELECT t.typname, e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid")
    )
    live: dict[str, set[str]] = {}
    for name, label in rows:
        live.setdefault(name, set()).add(label)
    return live


def _declared_unique_sets(table: Any) -> list[tuple[str, frozenset[str]]]:
    declared: list[tuple[str, frozenset[str]]] = []
    for constraint in table.constraints:
        if constraint.__class__.__name__ == "UniqueConstraint" and len(constraint.columns):
            declared.append((constraint.name or "unnamed", frozenset(c.name for c in constraint.columns)))
    for index in table.indexes:
        if index.unique:
            declared.append((index.name or "unnamed", frozenset(c.name for c in index.columns)))
    for column in table.columns:
        if column.unique:
            declared.append((f"{table.name}_{column.name}_key", frozenset({column.name})))
    return declared


def _live_unique_sets(inspector: Any, table_name: str) -> set[frozenset[str]]:
    live = {frozenset(item["column_names"]) for item in inspector.get_unique_constraints(table_name)}
    live |= {
        frozenset(c for c in item["column_names"] if c)
        for item in inspector.get_indexes(table_name)
        if item.get("unique")
    }
    primary = inspector.get_pk_constraint(table_name).get("constrained_columns") or []
    if primary:
        live.add(frozenset(primary))
    return live


def collect_issues(connection: Connection, metadata: MetaData) -> list[Issue]:
    inspector = inspect(connection)
    live_tables = set(inspector.get_table_names())
    issues: list[Issue] = []

    for table in metadata.sorted_tables:
        if table.name not in live_tables:
            issues.append({"kind": "missing_table", "table": table.name, "detail": table.name})
            continue
        live_columns = {column["name"] for column in inspector.get_columns(table.name)}
        for column in table.columns:
            if column.name not in live_columns:
                issues.append(
                    {"kind": "missing_column", "table": table.name, "detail": column.name}
                )
        live_unique = _live_unique_sets(inspector, table.name)
        for name, columns in _declared_unique_sets(table):
            if columns <= live_columns and columns not in live_unique:
                issues.append(
                    {
                        "kind": "missing_unique",
                        "table": table.name,
                        "detail": f"{name} ({', '.join(sorted(columns))})",
                    }
                )

    if connection.dialect.name == "postgresql":
        live_enums = _live_enums(connection)
        for type_name, labels in sorted(_model_enums(metadata).items()):
            if type_name not in live_enums:
                issues.append({"kind": "missing_enum", "table": None, "detail": type_name})
                continue
            for label in sorted(labels - live_enums[type_name]):
                issues.append(
                    {"kind": "missing_enum_label", "table": None, "detail": f"{type_name}.{label}"}
                )
    return issues


async def check_schema_drift(engine: AsyncEngine, metadata: MetaData | None = None) -> dict[str, Any]:
    async with engine.connect() as connection:
        issues = await connection.run_sync(collect_issues, metadata or Base.metadata)
    return {
        "ok": not issues,
        "checked_at": datetime.now(timezone.utc).isoformat(),
        "issue_count": len(issues),
        "issues": issues,
    }
