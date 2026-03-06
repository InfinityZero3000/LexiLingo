#!/usr/bin/env bash
# Production entrypoint — handles fresh DB init + incremental migrations.
#
# Logic:
#   First deployment  → create_tables.py (create_all) + alembic stamp head
#   Re-deployment     → alembic upgrade head (incremental)
#
# Usage:
#   ./scripts/entrypoint.sh            (production)
#   DATABASE_URL=postgresql+asyncpg://... ./scripts/entrypoint.sh

set -euo pipefail

echo "=== LexiLingo Backend Startup ==="
echo "DATABASE_URL: ${DATABASE_URL:-<not set>}"

# Check whether alembic_version table exists (means DB was previously managed by Alembic).
DB_INITIALISED=$(python - <<'EOF'
import asyncio, sys, os
from app.core.config import settings
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy import text

url = settings.async_database_url
if not url or url.startswith("sqlite"):
    print("False")
    sys.exit(0)

async def check() -> bool:
    engine = create_async_engine(url, pool_size=1, max_overflow=0)
    try:
        async with engine.connect() as conn:
            result = await conn.execute(text(
                "SELECT COUNT(*) FROM information_schema.tables "
                "WHERE table_schema = 'public' AND table_name = 'alembic_version'"
            ))
            return result.scalar() > 0
    except Exception as e:
        print(f"DB check error: {e}", file=sys.stderr)
        return False
    finally:
        await engine.dispose()

print(str(asyncio.run(check())))
EOF
)

if [ "$DB_INITIALISED" = "False" ]; then
    echo ">>> Fresh database detected — running create_all + alembic stamp head..."
    python create_tables.py
    alembic stamp head
    echo ">>> Schema initialised."
else
    echo ">>> Existing database — applying pending Alembic migrations..."
    alembic upgrade head
    echo ">>> Migrations applied."
fi

echo ">>> Starting Uvicorn..."
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --workers "${UVICORN_WORKERS:-1}"
