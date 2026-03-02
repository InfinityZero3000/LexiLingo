# Sections

This file defines all sections, their ordering, impact levels, and descriptions.

---

## 1. Route Pattern (route)

**Impact:** CRITICAL  
**Description:** FastAPI route function conventions: ApiResponse[T] envelope, auth dependencies, error handling with HTTPException, async/await, and logging.

## 2. Schema Pattern (schema)

**Impact:** HIGH  
**Description:** Pydantic v2 schema conventions for request and response models. Field definitions, validators, and file organization.

## 3. Query Pattern (query)

**Impact:** HIGH  
**Description:** Async SQLAlchemy 2.0 query patterns: select(), execute(), scalars(), joins, aggregations.

## 4. Migration Pattern (migration)

**Impact:** HIGH  
**Description:** Alembic migration workflow: creating, reviewing, and applying schema migrations safely.
