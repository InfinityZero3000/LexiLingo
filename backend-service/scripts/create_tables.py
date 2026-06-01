#!/usr/bin/env python3
"""Create all DB tables directly from SQLAlchemy models.

Used by CI to initialise a fresh test database without relying on
Alembic migration history (which may reference tables from earlier
migrations that haven't run yet in a clean environment).
"""

import asyncio
import sys
from pathlib import Path

# Allow `from app.*` imports when run from the backend-service directory.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.core.database import Base, engine  # noqa: E402 — path must be set first
import app.models  # noqa: F401 — registers all ORM models on Base.metadata


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    print("All tables created successfully.")
    await engine.dispose()


if __name__ == "__main__":
    asyncio.run(main())
