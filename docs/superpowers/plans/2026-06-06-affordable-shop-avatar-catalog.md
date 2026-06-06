# Affordable Shop And Avatar Catalog Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the shop with affordable functional items and 36 permanent,
equippable exclusive avatars.

**Architecture:** A shared backend catalog defines item metadata and an
idempotent migration applies it to existing databases. Inventory effects remain
server-authoritative; avatar equip validates ownership, and Flutter maps the
existing API schema into categories and renders/equips owned avatars.

**Tech Stack:** FastAPI, SQLAlchemy, Alembic, PostgreSQL/SQLite, Flutter,
Provider, DiceBear SVG, pytest, flutter_test

---

## Chunk 1: Backend Catalog And Economy

### Task 1: Define and migrate the catalog

**Files:**
- Create: `backend-service/app/core/shop_catalog.py`
- Create: `backend-service/alembic/versions/add_affordable_shop_avatar_catalog.py`
- Modify: `backend-service/app/routes/admin.py`
- Test: `backend-service/tests/test_shop_catalog.py`

- [x] Define four repriced items, five new consumables, and 36 avatar items.
- [x] Add an idempotent migration that updates existing rows and inserts missing
  rows by unique item name.
- [x] Reuse the catalog in development sample seeding.
- [x] Test item counts, price ranges, avatar URLs, and effect metadata.

## Chunk 2: Real Effects And Avatar Ownership

### Task 2: Persist real lesson consumable effects

**Files:**
- Modify: `backend-service/app/models/progress.py`
- Modify: `backend-service/app/routes/learning.py`
- Modify: `backend-service/app/services/item_effects_service.py`
- Modify: `backend-service/app/schemas/progress.py`
- Test: `backend-service/tests/test_item_effects_service.py`

- [x] Add `bonus_hints` to lesson attempts.
- [x] Include bonus hints in start and answer responses.
- [x] Make hint packs and heart refills update an unfinished attempt.
- [x] Respect configurable streak-freeze quantities and XP durations.

### Task 3: Add permanent avatar equip

**Files:**
- Modify: `backend-service/app/crud/gamification.py`
- Modify: `backend-service/app/routes/gamification.py`
- Modify: `backend-service/app/schemas/gamification.py`
- Test: `backend-service/tests/test_gamification_routes.py`

- [x] Reject repeated avatar purchases already owned by the user.
- [x] Add an equip endpoint that validates owned avatar inventory.
- [x] Update `users.avatar_url` without decrementing inventory.
- [x] Return the equipped URL and refreshed user state.

## Chunk 3: Flutter Shop And Profile

### Task 4: Correct shop entity mapping and card rendering

**Files:**
- Modify: `flutter-app/lib/features/gamification/domain/entities/shop_item.dart`
- Modify: `flutter-app/lib/features/gamification/presentation/widgets/shop_item_card.dart`
- Modify: `flutter-app/lib/features/gamification/presentation/screens/shop_screen.dart`
- Test: `flutter-app/test/features/gamification/shop_item_test.dart`

- [x] Map backend `item_type`, `effects`, and stock fields correctly.
- [x] Derive shop categories from supported item types.
- [x] Render avatar SVG/PNG URLs in cards and dialogs.
- [x] Show owned state and prevent duplicate avatar purchases.

### Task 5: Equip and reselect purchased avatars

**Files:**
- Modify: `flutter-app/lib/features/gamification/presentation/providers/gamification_provider.dart`
- Modify: `flutter-app/lib/features/profile/presentation/pages/edit_profile_screen.dart`
- Modify: `flutter-app/assets/i18n/en.json`
- Modify: `flutter-app/assets/i18n/vi.json`
- Test: `flutter-app/test/features/gamification/avatar_inventory_test.dart`

- [x] Fix inventory use request to match the backend request schema.
- [x] Add provider method for permanent avatar equip.
- [x] Offer "Equip now" after avatar purchase.
- [x] Merge owned avatar URLs into the profile picker.
- [x] Add localized user-facing strings.

## Chunk 4: Verification

### Task 6: Run focused and static checks

- [x] Run backend catalog, effect, and gamification route tests.
- [x] Run Flutter shop/avatar tests.
- [x] Run Python compilation or lint checks on modified backend files.
- [x] Run `flutter analyze` on modified Flutter files.
- [x] Review the final diff for unrelated worktree changes.
