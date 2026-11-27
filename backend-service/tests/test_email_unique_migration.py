"""The email index migration must enforce uniqueness when it can, and never block a deploy."""

import os
import subprocess
import sys
from pathlib import Path

import asyncpg
import pytest
from sqlalchemy.engine import make_url

from tests.conftest import TEST_DATABASE_URL

BACKEND_ROOT = Path(__file__).resolve().parents[1]
BEFORE = "e9b4c2a7f1d8"
INSERT = (
    "INSERT INTO users (id, email, username, hashed_password, native_language, target_language, level, "
    "certified_level, lexi_reply_language, total_xp, numeric_level, rank, rank_score, rank_level_score, "
    "rank_proficiency_score, is_onboarding_completed, has_seeded_basic_words, is_active, is_verified, provider, "
    "created_at, updated_at) "
    "VALUES (gen_random_uuid(), $1, $2, 'x', 'vi', 'en', 'A1', 'A1', 'app', 0, 1, 'bronze', 0, 0, 0, "
    "false, false, true, true, '[\"local\"]', now(), now())"
)


def _alembic(url, *args: str) -> None:
    subprocess.run(
        [sys.executable, "-m", "alembic", *args], cwd=BACKEND_ROOT, check=True, capture_output=True,
        env={**os.environ, "DATABASE_URL": url.render_as_string(hide_password=False)},
    )


@pytest.mark.parametrize("has_duplicates", [False, True])
async def test_email_index_migration(has_duplicates):
    url = make_url(TEST_DATABASE_URL)
    name = url.database.removesuffix("_test") + "_email_index_test"
    chain = url.set(database=name)
    admin = await asyncpg.connect(
        url.set(drivername="postgresql", database="postgres").render_as_string(hide_password=False)
    )
    try:
        await admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        await admin.execute(f'CREATE DATABASE "{name}"')
        _alembic(chain, "upgrade", BEFORE)
        dsn = chain.set(drivername="postgresql").render_as_string(hide_password=False)
        conn = await asyncpg.connect(dsn)
        try:
            await conn.execute(INSERT, "Someone@example.com", "first")
            if has_duplicates:
                await conn.execute(INSERT, "someone@example.com", "second")
        finally:
            await conn.close()

        _alembic(chain, "upgrade", "head")

        conn = await asyncpg.connect(dsn)
        try:
            indexes = {
                r["indexname"]
                for r in await conn.fetch("SELECT indexname FROM pg_indexes WHERE tablename = 'users'")
            }
            if has_duplicates:
                assert "ix_users_email_lower" in indexes and "uq_users_email_lower" not in indexes
            else:
                assert "uq_users_email_lower" in indexes
                with pytest.raises(asyncpg.UniqueViolationError):
                    await conn.execute(INSERT, "SOMEONE@example.com", "third")
        finally:
            await conn.close()

        _alembic(chain, "downgrade", BEFORE)
    finally:
        await admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
        await admin.close()
