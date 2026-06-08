# Game and Vocabulary API Compatibility Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent unsupported starter reward and vocabulary collection requests from reaching production.

**Architecture:** Gate the optional starter reward client flow behind an environment-backed capability flag and retain a vocabulary page size supported by old and new backends. Add request-level Flutter tests and boundary-level FastAPI tests to keep both contracts stable.

**Tech Stack:** Flutter, Provider, flutter_dotenv, package:http testing, FastAPI, pytest, HTTPX.

---

## Chunk 1: Flutter Compatibility

### Task 1: Gate starter reward requests

**Files:**
- Modify: `flutter-app/lib/core/network/api_config.dart`
- Modify: `flutter-app/lib/features/gamification/presentation/providers/gamification_provider.dart`
- Modify: `.github/workflows/cd.yml`
- Create: `flutter-app/test/core/network/api_config_starter_reward_test.dart`
- Create: `flutter-app/test/features/gamification/gamification_provider_starter_reward_test.dart`

- [x] Add failing provider tests for disabled and enabled starter reward flows.
- [x] Add `ApiConfig.enableStarterReward`.
- [x] Make `GamificationProvider` injectable and skip reward requests when disabled.
- [x] Set `ENABLE_STARTER_REWARD=false` in the production build config.
- [x] Run the focused provider tests.

### Task 2: Lock the deck collection request

**Files:**
- Modify: `flutter-app/lib/features/vocabulary/presentation/providers/vocab_provider.dart`
- Modify: `flutter-app/test/features/vocabulary/presentation/providers/vocab_provider_quick_save_test.dart`

- [x] Add a failing assertion for `limit=100`.
- [x] Replace the inline page size with a named compatibility constant.
- [x] Run the focused vocabulary provider test.

## Chunk 2: Backend Contract and Verification

### Task 3: Test vocabulary pagination boundaries

**Files:**
- Modify: `backend-service/tests/test_vocabulary_routes.py`

- [x] Add tests for accepted `limit=100` and rejected `limit=1001`.
- [x] Run the focused backend route tests.

### Task 4: Verify the complete fix

**Files:**
- Review all files changed in Tasks 1-3.

- [x] Run Dart formatting.
- [x] Run focused Flutter tests.
- [x] Run focused backend tests.
- [x] Run `flutter analyze`.
- [x] Review the diff for accidental changes and contract regressions.
