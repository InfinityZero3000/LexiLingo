"""
Import reference content written by export_reference_content.py.

Upserts vocabulary_items and question_bank by id. Never deletes.

  default   insert rows whose id is absent; existing rows are left alone
  --update  also overwrite rows whose values differ

Dry run unless --write: everything executes, then the transaction rolls back.
Any invalid row (unknown part_of_speech / difficulty_level, bad UUID, duplicate)
refuses the whole import with a message naming it.

Run (inside the backend-service container, or with DATABASE_URL set):
    python3 scripts/import_reference_content.py --dir content
    python3 scripts/import_reference_content.py --dir content --write
    python3 scripts/import_reference_content.py --dir content --write --update
"""

import argparse
import asyncio
import os
import sys
from pathlib import Path

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.reference_content import (  # noqa: E402
    ReferenceContentError,
    import_reference,
    load_reference_dir,
)


def _async_dsn(dsn: str) -> str:
    for prefix in ("postgresql://", "postgres://"):
        if dsn.startswith(prefix):
            return "postgresql+asyncpg://" + dsn[len(prefix):]
    return dsn


async def main(dsn: str, root: Path, write: bool, overwrite: bool) -> int:
    payload = load_reference_dir(root)
    if not any(payload.values()):
        print(f"no reference files found under {root}")
        return 1
    engine = create_async_engine(_async_dsn(dsn))
    try:
        async with AsyncSession(engine) as session:
            report = await import_reference(session, payload, overwrite=overwrite)
            print("\n".join(report.lines(write=write)))
            if write:
                await session.commit()
                print("\nImported.")
            else:
                await session.rollback()
                print("\nDRY RUN: nothing was written. Re-run with --write to apply.")
    finally:
        await engine.dispose()
    return 0


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--dir", type=Path, default=Path("content"), help="parent of vocabulary/ and questions/")
    p.add_argument("--write", action="store_true", help="apply (default is dry run)")
    p.add_argument("--update", action="store_true", help="overwrite rows that already exist")
    p.add_argument("--dsn", default=os.getenv("DATABASE_URL", ""))
    args = p.parse_args()
    if not args.dsn:
        sys.exit("set --dsn or DATABASE_URL")
    try:
        sys.exit(asyncio.run(main(args.dsn, args.dir, args.write, args.update)))
    except ReferenceContentError as exc:
        sys.exit(f"REFUSED: {exc}")
