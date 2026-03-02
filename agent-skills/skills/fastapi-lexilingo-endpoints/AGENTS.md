# LexiLingo Team - Fastapi Lexilingo Endpoints

**Version 1.0.0**  
LexiLingo Team  
March 2026

> **Note:**  
> This document is mainly for agents and LLMs to follow when maintaining,  
> generating, or refactoring code. Humans may also find it useful, but guidance  
> here is optimized for automation and consistency by AI-assisted workflows.

---

## Abstract

FastAPI endpoint and schema patterns for the LexiLingo backend-service. Covers the ApiResponse[T] envelope, Pydantic v2 schema conventions, async SQLAlchemy query patterns, Alembic migration workflow, and service layer composition. Apply these when adding endpoints like GET /api/users/me/stats, /me/level, /me/weekly-activity, /api/courses/categories, /api/progress/weekly.

---

## Table of Contents

1. [Route Pattern](##1-route-pattern)
2. [Schema Pattern](##2-schema-pattern)
4. [Migration Pattern](##4-migration-pattern)

---

## 1. Route Pattern

**Impact: CRITICAL**

FastAPI route function conventions: ApiResponse[T] envelope, auth dependencies, error handling with HTTPException, async/await, and logging.

### 1.1 Untitled

**Impact: CRITICAL**



---

## 2. Schema Pattern

**Impact: HIGH**

Pydantic v2 schema conventions for request and response models. Field definitions, validators, and file organization.

### 2.1 Untitled

**Impact: HIGH**



---

## 4. Migration Pattern

**Impact: HIGH**

Alembic migration workflow: creating, reviewing, and applying schema migrations safely.

### 4.1 Untitled

**Impact: HIGH**



---

## References

1. [https://fastapi.tiangolo.com/tutorial/](https://fastapi.tiangolo.com/tutorial/)
2. [https://docs.pydantic.dev/latest/](https://docs.pydantic.dev/latest/)
3. [https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html](https://docs.sqlalchemy.org/en/20/orm/extensions/asyncio.html)
4. [https://alembic.sqlalchemy.org/en/latest/tutorial.html](https://alembic.sqlalchemy.org/en/latest/tutorial.html)
