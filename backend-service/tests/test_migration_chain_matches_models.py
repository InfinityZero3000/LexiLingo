"""A database built by `alembic upgrade head` must accept what the models write."""

import os
import subprocess
import sys
from pathlib import Path

import asyncpg
from sqlalchemy import Enum as SQLEnum
from sqlalchemy.engine import make_url

from app.core.database import Base
from tests.conftest import TEST_DATABASE_URL

BACKEND_ROOT = Path(__file__).resolve().parents[1]


async def test_migrated_schema_has_model_enum_labels_and_columns():
    url = make_url(TEST_DATABASE_URL)
    name = url.database.removesuffix("_test") + "_chain_test"
    chain_url = url.set(database=name)
    dsn = url.set(drivername="postgresql", database="postgres")
    admin = await asyncpg.connect(dsn.render_as_string(hide_password=False))
    try:
        await admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        await admin.execute(f'CREATE DATABASE "{name}"')
        subprocess.run(
            [sys.executable, "-m", "alembic", "upgrade", "head"],
            cwd=BACKEND_ROOT,
            env={**os.environ, "DATABASE_URL": chain_url.render_as_string(hide_password=False)},
            check=True,
            capture_output=True,
        )
        conn = await asyncpg.connect(
            chain_url.set(drivername="postgresql").render_as_string(hide_password=False)
        )
        try:
            labels: dict[str, set[str]] = {}
            for row in await conn.fetch(
                "SELECT t.typname, e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid"
            ):
                labels.setdefault(row["typname"], set()).add(row["enumlabel"])
            columns: dict[str, set[str]] = {}
            for row in await conn.fetch(
                "SELECT table_name, column_name FROM information_schema.columns "
                "WHERE table_schema = 'public'"
            ):
                columns.setdefault(row["table_name"], set()).add(row["column_name"])
        finally:
            await conn.close()
    finally:
        await admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        await admin.close()

    problems = []
    for table in Base.metadata.sorted_tables:
        missing = {c.name for c in table.columns} - columns.get(table.name, set())
        if missing:
            problems.append(f"{table.name}: missing columns {sorted(missing)}")
        for column in table.columns:
            if isinstance(column.type, SQLEnum) and column.type.name in labels:
                absent = set(column.type.enums) - labels[column.type.name]
                if absent:
                    problems.append(f"{column.type.name}: missing labels {sorted(absent)}")
    assert not problems, "\n".join(sorted(set(problems)))
