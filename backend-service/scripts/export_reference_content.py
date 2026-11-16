"""
Export reference content (vocabulary_items, question_bank) to committed JSON.

Read-only: runs in a READ ONLY transaction and never writes to the database.
Output is deterministic (sorted, 2-space indent, UTF-8, trailing newline), so an
unchanged database re-exports with no diff:

    content/vocabulary/vocabulary_items.<A1..C2>.json
    content/vocabulary/manifest.json        (counts only)
    content/questions/question_bank.json

--seed-csv PATH also writes a CSV (word,part_of_speech,cefr_level,definition,example)
that the content-agent "admin_upload" source accepts as a labelled seed.

Run (inside the backend-service container, or with DATABASE_URL set):
    python3 scripts/export_reference_content.py --out-dir content
"""

import argparse
import asyncio
import os
import sys
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

sys.path.insert(0, str(Path(__file__).parent.parent))

from app.services.reference_content import (  # noqa: E402
    build_files,
    fetch_reference,
    seed_csv,
    write_files,
)


def _async_dsn(dsn: str) -> str:
    for prefix in ("postgresql://", "postgres://"):
        if dsn.startswith(prefix):
            return "postgresql+asyncpg://" + dsn[len(prefix):]
    return dsn


async def main(dsn: str, out_dir: Path, csv_path: Path | None, write_json: bool) -> None:
    engine = create_async_engine(_async_dsn(dsn))
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SET TRANSACTION READ ONLY"))
            payload = await fetch_reference(conn)
            await conn.rollback()
    finally:
        await engine.dispose()

    for table, rows in payload.items():
        print(f"  {table}: {len(rows)} rows")
    if write_json:
        files = build_files(payload)
        write_files(files, out_dir)
        print(f"\nWrote {len(files)} file(s) under {out_dir}")
    if csv_path:
        csv_path.parent.mkdir(parents=True, exist_ok=True)
        csv_path.write_text(seed_csv(payload["vocabulary_items"]), encoding="utf-8")
        print(f"Wrote admin_upload seed CSV: {csv_path}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", type=Path, default=Path("content"), help="parent of vocabulary/ and questions/")
    p.add_argument("--seed-csv", type=Path, help="also write an admin_upload CSV seed here")
    p.add_argument("--csv-only", action="store_true", help="with --seed-csv: skip the JSON files")
    p.add_argument("--dsn", default=os.getenv("DATABASE_URL", ""))
    args = p.parse_args()
    if not args.dsn:
        sys.exit("set --dsn or DATABASE_URL")
    if args.csv_only and not args.seed_csv:
        sys.exit("--csv-only needs --seed-csv")
    asyncio.run(main(args.dsn, args.out_dir, args.seed_csv, not args.csv_only))
