#!/usr/bin/env bash
# Production entrypoint — handles fresh DB init + incremental migrations.
#
# Logic:
#   First deployment   → create_tables.py (create_all) + alembic stamp head
#   Re-deployment      → alembic upgrade head (incremental)
#   DB unreachable     → skip migration step, start API so Render can bind port
#
# Usage:
#   ./scripts/entrypoint.sh            (production)
#   DATABASE_URL=postgresql+asyncpg://... ./scripts/entrypoint.sh

set -euo pipefail

echo "=== LexiLingo Backend Startup ==="
if [ -n "${DATABASE_URL:-}" ]; then
    echo "DATABASE_URL: <configured>"
else
    echo "DATABASE_URL: <not set>"
fi

# Check whether alembic_version table exists (means DB was previously managed by Alembic).
DB_STATE=$(python - <<'EOF'
import asyncio, sys, os
from app.core.config import settings
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy import text

url = settings.async_database_url
if not url or url.startswith("sqlite"):
    print("skip")
    sys.exit(0)

async def check() -> bool:
    engine = create_async_engine(url, pool_size=1, max_overflow=0)
    try:
        async with engine.connect() as conn:
            result = await conn.execute(text(
                "SELECT COUNT(*) FROM information_schema.tables "
                "WHERE table_schema = 'public' AND table_name = 'alembic_version'"
            ))
            return "existing" if result.scalar() > 0 else "fresh"
    except Exception as e:
        print(f"DB check failed ({type(e).__name__})", file=sys.stderr)
        return "unreachable"
    finally:
        await engine.dispose()

print(str(asyncio.run(check())))
EOF
)

case "$DB_STATE" in
    fresh)
        echo ">>> Fresh database detected — running create_all + alembic stamp head..."
        python scripts/create_tables.py
        alembic stamp head
        echo ">>> Schema initialised."
        ;;
    existing)
        echo ">>> Existing database — applying pending Alembic migrations..."
        alembic upgrade head
        echo ">>> Migrations applied."
        ;;
    unreachable)
        echo ">>> WARNING: Database unreachable during startup probe. Skipping migrations and continuing to bind API port."
        echo ">>> WARNING: Check DATABASE_URL / network access on Render. Readiness checks may fail until DB is reachable."
        ;;
    skip)
        echo ">>> No production PostgreSQL database configured — skipping migration bootstrap."
        ;;
    *)
        echo ">>> ERROR: Unexpected database probe result: $DB_STATE"
        exit 1
        ;;
esac

echo ">>> Starting Uvicorn..."
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --workers "${UVICORN_WORKERS:-1}" \
    --proxy-headers \
    --forwarded-allow-ips="*"
