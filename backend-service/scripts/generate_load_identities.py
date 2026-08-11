#!/usr/bin/env python3
"""Seed isolated load-test users and write a short-lived Locust identity pool."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import stat
import sys
import tempfile
import uuid
from pathlib import Path

from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.engine import make_url

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.database import AsyncSessionLocal  # noqa: E402
from app.core.security import create_access_token  # noqa: E402
from app.models.user import User  # noqa: E402


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def _require_test_database() -> None:
    database_url = os.getenv("DATABASE_URL", "")
    if not database_url:
        raise RuntimeError("DATABASE_URL is required")
    database_name = make_url(database_url).database or ""
    if not database_name.endswith("_test"):
        raise RuntimeError("refusing to seed a database without a _test suffix")


async def _seed_users(user_ids: list[uuid.UUID]) -> None:
    rows = [
        {
            "id": user_id,
            "email": f"trace-load-{user_id.hex}@example.com",
            "username": f"trace_load_{user_id.hex}",
            "hashed_password": "!load-login-disabled!",
            "display_name": "TRACE-CAG load user",
            "is_active": True,
            "is_verified": True,
            "native_language": "vi",
            "target_language": "en",
            "level": "B1",
        }
        for user_id in user_ids
    ]
    async with AsyncSessionLocal() as session:
        await session.execute(
            insert(User).values(rows).on_conflict_do_nothing(index_elements=["id"])
        )
        await session.commit()


def main() -> int:
    args = _parse_args()
    if not 1 <= args.count <= 10_000:
        raise ValueError("count must be between 1 and 10000")
    _require_test_database()

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.is_symlink():
        raise RuntimeError("refusing to replace a symlink identity file")
    if args.output.exists() and stat.S_IMODE(args.output.stat().st_mode) & 0o077:
        raise RuntimeError("refusing to replace an insecure identity file")
    user_ids = [uuid.uuid4() for _ in range(args.count)]
    asyncio.run(_seed_users(user_ids))
    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{args.output.name}.", dir=args.output.parent
    )
    os.chmod(fd, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as destination:
            for user_id in user_ids:
                destination.write(
                    json.dumps(
                        {
                            "user_id": str(user_id),
                            "token": create_access_token(
                                {"sub": str(user_id), "role": "user"}
                            ),
                        }
                    )
                    + "\n"
                )
            destination.flush()
            os.fsync(destination.fileno())
        os.replace(temporary_name, args.output)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
    print(f"seeded {args.count} load identities at {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
