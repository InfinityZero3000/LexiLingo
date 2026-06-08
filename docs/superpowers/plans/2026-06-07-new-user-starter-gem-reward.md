# New User Starter Gem Reward Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grant every newly created learner account 100 Gems exactly once and show the reward only after the user reaches the main Flutter interface.

**Architecture:** A backend reward-grant record is the idempotent source of truth. User creation, wallet credit, wallet transaction, and durable notification share one database transaction; Flutter queries pending state from `MainScreen`, shows the reward modal, acknowledges it, and then displays an in-app confirmation banner.

**Tech Stack:** FastAPI, SQLAlchemy async, Alembic, PostgreSQL/SQLite tests, Firebase Admin FCM, Flutter, Provider, easy_localization.

---

## Chunk 1: Backend Reward Grant

### Task 1: Persist and grant the starter reward

**Files:**
- Create: `backend-service/app/models/reward_grant.py`
- Create: `backend-service/alembic/versions/add_new_user_starter_reward.py`
- Create: `backend-service/app/services/starter_reward_service.py`
- Modify: `backend-service/app/models/__init__.py`
- Modify: `backend-service/app/crud/gamification.py`
- Test: `backend-service/tests/services/test_starter_reward_service.py`

- [x] Write tests for a 100-Gem grant, durable notification, and idempotent retry.
- [x] Add the reward-grant model and migration with unique `(user_id, reward_key)`.
- [x] Allow wallet creation/addition to participate in caller-managed transactions.
- [x] Implement `StarterRewardService.grant_new_user_reward`.
- [x] Run the focused service tests.

### Task 2: Integrate every learner account creation path

**Files:**
- Modify: `backend-service/app/routes/auth.py`
- Modify: `backend-service/app/core/firebase_auth.py`
- Test: `backend-service/tests/test_auth_routes.py`
- Test: `backend-service/tests/test_firebase_auth.py`

- [x] Add failing tests asserting new email and social learner users call the grant service.
- [x] Flush new users, grant the reward, then commit once.
- [x] Keep existing-user login/provider linking and admin creation ineligible.
- [x] Run focused authentication tests.

## Chunk 2: Reward Status and Push

### Task 3: Add pending/seen reward API

**Files:**
- Modify: `backend-service/app/schemas/gamification.py`
- Modify: `backend-service/app/routes/gamification.py`
- Test: `backend-service/tests/test_gamification_routes.py`

- [x] Add tests for pending, absent, and idempotent seen responses.
- [x] Implement authenticated pending and seen endpoints.
- [x] Invalidate wallet cache where appropriate.
- [x] Run focused gamification tests.

### Task 4: Deliver an unsent push after device registration

**Files:**
- Modify: `backend-service/app/services/push_notification_service.py`
- Modify: `backend-service/app/services/starter_reward_service.py`
- Modify: `backend-service/app/routes/devices.py`
- Test: `backend-service/tests/test_push_notification_service.py`
- Test: `backend-service/tests/test_devices_routes.py`

- [x] Add tests for starter-reward FCM payload and device-registration delivery hook.
- [x] Add generic starter-reward multicast delivery.
- [x] Retry unsent grants when a usable FCM token is registered.
- [x] Record `push_sent_at` only after successful delivery.
- [x] Run focused push/device tests.

## Chunk 3: Flutter Main-Screen Presentation

### Task 5: Add reward state and API methods

**Files:**
- Create: `flutter-app/lib/features/gamification/domain/entities/starter_reward.dart`
- Modify: `flutter-app/lib/features/gamification/presentation/providers/gamification_provider.dart`
- Test: `flutter-app/test/features/gamification/starter_reward_test.dart`

- [x] Test JSON parsing and pending/seen provider behavior.
- [x] Add pending-reward loading and acknowledgement methods.
- [x] Ensure wallet refresh remains server-authoritative.
- [x] Run focused Flutter tests.

### Task 6: Add B modal and C confirmation banner

**Files:**
- Create: `flutter-app/lib/features/gamification/presentation/widgets/starter_reward_dialog.dart`
- Modify: `flutter-app/lib/features/home/presentation/pages/main_screen.dart`
- Modify: `flutter-app/assets/i18n/en.json`
- Modify: `flutter-app/assets/i18n/vi.json`
- Test: `flutter-app/test/features/gamification/starter_reward_dialog_test.dart`

- [x] Add widget tests for the non-dismissible modal and localized amount.
- [x] Build the centered B-style modal using semantic theme colors.
- [x] Build the temporary C-style in-app confirmation banner.
- [x] Trigger the flow only from `MainScreen` after its first frame.
- [x] Acknowledge after modal action; show C only after successful acknowledgement.
- [x] Run focused widget tests.

### Task 7: Preserve foreground/background notification behavior

**Files:**
- Modify: `flutter-app/lib/core/services/firebase_messaging_service.dart`
- Test: `flutter-app/test/core/services/firebase_messaging_service_test.dart`

- [x] Ensure foreground starter messages do not open reward UI or create a system-style popup.
- [x] Keep background/terminated taps routed to the main interface.
- [x] Run focused messaging tests where the Firebase singleton permits it.

## Chunk 4: Review and Verification

### Task 8: Verify and review the complete feature

**Files:**
- Review all files changed by Tasks 1-7.

- [x] Run backend focused tests.
- [x] Run Alembic upgrade/downgrade validation or migration syntax checks.
- [x] Run Dart formatting.
- [x] Run focused Flutter tests.
- [x] Run `flutter analyze` on touched Flutter files.
- [x] Review the diff for duplicate grants, transaction boundaries, push retries, mounted-context safety, accessibility, and unrelated changes.
- [x] Fix findings and rerun affected checks.
