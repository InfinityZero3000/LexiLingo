# FastAPI LexiLingo Endpoints

Backend endpoint patterns for LexiLingo. Covers `ApiResponse[T]` envelope, Pydantic v2, async SQLAlchemy 2.0, service layer, and Alembic migrations.

## Key Rules

| Rule | Impact |
|------|--------|
| `route-apiresponse-envelope` | CRITICAL |
| `schema-pydantic-v2-conventions` | HIGH |
| `migration-alembic-workflow` | HIGH |

## Existing Endpoints (already done)

- `GET /api/users/me/stats` → `routes/users.py:186`
- `GET /api/users/me/level` → `routes/users.py:118`
- `GET /api/users/me/weekly-activity` → `routes/users.py:283`
- `POST /api/xp/award` → `routes/xp.py`

See [AGENTS.md](./AGENTS.md) for full patterns.
