# Balanced Basic Vocabulary Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and migrate a balanced, valid 200-word starter vocabulary catalog across the six system topics.

**Architecture:** Put vocabulary quality and balancing rules in a pure policy module, call it from CRUD/runtime paths, and reuse it from an Alembic migration that repairs existing catalogs and seeded users. Keep the Flutter API contract unchanged while filtering malformed content at the backend boundary.

**Tech Stack:** Python 3, SQLAlchemy 2 async ORM, Alembic, PostgreSQL/SQLite-compatible tests, FastAPI, pytest.

---

## Chunk 1: Catalog Policy and Runtime Protection

### Task 1: Add vocabulary catalog policy

**Files:**
- Create: `backend-service/app/services/vocabulary_catalog_policy.py`
- Create: `backend-service/tests/test_vocabulary_catalog_policy.py`

- [x] Write failing tests for placeholder detection, legacy tag normalization,
  deterministic ranking, uniqueness, and exact quotas of 34/34/33/33/33/33.
- [x] Run `pytest tests/test_vocabulary_catalog_policy.py -q` and verify failure.
- [x] Implement pure policy helpers and balanced selection.
- [x] Run the policy tests and verify they pass.

### Task 2: Apply the policy to vocabulary CRUD

**Files:**
- Modify: `backend-service/app/crud/vocabulary.py`
- Modify: `backend-service/tests/test_vocabulary_isolation.py`
- Modify: `backend-service/tests/test_vocabulary_routes.py`

- [x] Add failing tests proving invalid definitions are excluded from topic
  results, `daily` accepts `daily_life`, results are frequency-first, and seed
  catalogs contain exactly 200 valid unique items.
- [x] Run the focused tests and verify failure.
- [x] Add reusable valid-definition SQL predicates and canonical tag handling.
- [x] Make starter seeding validate the selected catalog before setting the
  user's seeded flag.
- [ ] Run PostgreSQL-backed focused tests and verify they pass. Local database
  access was blocked by the execution sandbox.

## Chunk 2: Existing Data Repair

### Task 3: Add balanced starter migration

**Files:**
- Create: `backend-service/alembic/versions/<revision>_rebalance_basic_vocabulary.py`
- Modify: `backend-service/scripts/tag_basic_words.py`
- Modify: `backend-service/scripts/verify_seeding.py`

- [x] Implement migration helpers that normalize string/list tags and call the
  shared selection policy.
- [x] Retag the catalog to exactly 200 balanced starter items.
- [x] Remove unreviewed placeholder and obsolete starter collection rows while
  preserving reviewed rows and custom-deck references.
- [x] Add missing selected starter rows for users already marked as seeded.
- [x] Update maintenance scripts to use validation and report per-topic counts.
- [x] Run migration/import checks available in the local test environment.

## Chunk 3: Verification and Review

### Task 4: Verify the complete change

**Files:**
- Review all files changed in Tasks 1-3.

- [ ] Run PostgreSQL-backed isolation and route tests. Local database access was
  blocked by the execution sandbox.
- [ ] Run the broader PostgreSQL-backed backend vocabulary test suite.
- [x] Run formatting/lint checks available for the backend.
- [x] Inspect the migration downgrade behavior and final diff.
- [x] Review for preservation of user review history and custom deck items.
