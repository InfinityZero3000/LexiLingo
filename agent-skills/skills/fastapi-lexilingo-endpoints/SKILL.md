---
name: lexilingo-fastapi-endpoints
description: FastAPI backend patterns for LexiLingo backend-service. Use when adding routes, Pydantic schemas, async SQLAlchemy queries, or Alembic migrations. Enforces the ApiResponse[T] envelope, async/await patterns, service-layer separation, and the existing schema file conventions.
license: MIT
metadata:
  author: LexiLingo Team
  version: "1.0.0"
---

# FastAPI Endpoint Patterns for LexiLingo

All backend endpoints follow the same three conventions:
1. Wrap response in `ApiResponse[T]` generic envelope
2. Use `async/await` with `AsyncSession` — never sync SQLAlchemy calls
3. Business logic lives in `app/services/`, not in route functions

## When to Apply

Use this skill when:
- Adding new routes to `backend-service/app/routes/`
- Creating new Pydantic schemas in `backend-service/app/schemas/`
- Writing async SQLAlchemy queries with `select()`, `func`, joins
- Running Alembic migrations for new models or columns
- Adding a new service class to `app/services/`

## Rule Categories by Priority

| Priority | Category          | Impact   | Prefix       |
|----------|-------------------|----------|--------------|
| 1        | Route Pattern     | CRITICAL | `route-`     |
| 2        | Schema Pattern    | HIGH     | `schema-`    |
| 3        | Query Pattern     | HIGH     | `query-`     |
| 4        | Migration Pattern | HIGH     | `migration-` |

## Quick Reference

### 1. Route Pattern (CRITICAL)
- `route-apiresponse-envelope` — Always wrap in `ApiResponse[T]`; return `data=` + `message=`
- `route-auth-dependency` — Use `get_current_user` + `Depends(get_db)` on every private route

### 2. Schema Pattern (HIGH)
- `schema-pydantic-v2-conventions` — `Field(...)` for required, `model_dump(exclude_unset=True)` for partial updates
- `schema-file-location` — One schema file per feature in `app/schemas/<feature>.py`

### 3. Query Pattern (HIGH)
- `query-async-sqlalchemy` — Use `await db.execute(select(...))` + `.scalars()` pattern

### 4. Migration Pattern (HIGH)
- `migration-alembic-workflow` — `alembic revision --autogenerate`, review, `alembic upgrade head`
