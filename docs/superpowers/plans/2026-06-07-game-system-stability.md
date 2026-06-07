# Game System Stability Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all six games stable end to end, align Flutter/backend contracts, enforce server-authoritative XP and rank rules, and deliver accessible error-tolerant game screens.

**Architecture:** Backend game endpoints issue persisted game sessions and return canonical payloads. A completion endpoint verifies session-bound results and delegates all XP, rank, leaderboard, streak, and achievement mutations to a transactional XP service. Flutter parses one canonical model per game, submits session results, and renders explicit loading, error, award, and retry states.

**Tech Stack:** Flutter/Dart, Riverpod, Dio, FastAPI, SQLAlchemy async, PostgreSQL, Alembic, Redis, pytest, flutter_test.

---

## Scope And Exit Criteria

This plan covers:

- Word Scramble
- Fill in the Blank
- Matching
- Spelling Bee
- Grammar Quiz
- Hangman
- XP awards, daily caps, streak multipliers, levels, ranks, leaderboards, and game achievements
- Loading, error, retry, accessibility, reduced motion, and truthful result UI

The work is complete only when:

- All six games load, play, finish, retry, and recover from API failures.
- Flutter and backend contract tests cover every game payload.
- A game reward can be granted only once for a valid server-issued session.
- The server calculates the final XP; clients cannot submit arbitrary `base_xp`.
- XP, profile level progress, rank, leaderboard, activity, and achievements update consistently.
- Tied leaderboard entries use one documented ranking policy.
- Failed XP awards are never displayed as earned XP.
- Relevant backend and Flutter test suites pass.
- Manual validation succeeds on narrow and wide layouts with reduced motion enabled.

## Working Rules

- Preserve unrelated dirty worktree changes.
- Stage and commit only files belonging to the current task.
- Run `git status --short` before every commit.
- Add a failing test before each behavioral fix.
- Keep compatibility fields only where an already released client requires them; document their removal date.
- Do not expose answer keys through a new session API beyond what current gameplay requires.

## Chunk 1: Contract Baseline

### Task 1: Lock Canonical Game Payloads With Backend Tests

**Files:**

- Create: `backend-service/tests/routes/test_games_contract.py`
- Modify: `backend-service/app/routes/games.py`

- [x] Add response contract tests for every game endpoint.

Before persisted sessions are introduced in Task 4, each response must contain:

```python
{
    "game": "<canonical game type>",
    "cefr_level": "A1",
    # game-specific payload and configuration
}
```

Task 4 adds the persisted `session_id` without introducing an ephemeral ID.

Game-specific required fields:

```text
word_scramble: scrambled_word, correct_word, hint, xp_value
fill_blank: sentence, correct_answer, options, explanation, xp_value
matching: words_column, definitions_column, variant, xp_value
spelling_bee: word, definition, example_sentence, audio_url, xp_value
grammar_quiz: question, options, correct_answer, explanation, xp_value
hangman: word, hint, definition, hints, base_xp, max_lives
```

- [x] Assert options are non-empty, answers are present where the current client needs them, and XP values are non-negative.
- [x] Run the new tests and confirm they fail against the current mismatched responses.

Run:

```bash
cd backend-service
DEBUG=false pytest tests/routes/test_games_contract.py -q
```

Expected: failures identify Matching naming, Hangman fields, missing XP configuration, and malformed payloads.

- [x] Normalize response field names in `games.py`.
- [x] Retain old aliases only when compatibility is necessary:

```python
"variant": variant,
"variation": variant,  # temporary compatibility alias
```

- [x] Re-run the test.

Expected: all contract tests pass.

- [ ] Commit:

```bash
git add backend-service/app/routes/games.py backend-service/tests/routes/test_games_contract.py
git commit -m "test: define canonical game API contracts"
```

### Task 2: Align Flutter Models And Repository Parameters

**Files:**

- Modify: `flutter-app/lib/features/games/domain/entities/game_entities.dart`
- Modify: `flutter-app/lib/features/games/data/repositories/games_repository.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/matching_game_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/grammar_quiz_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/hangman_screen.dart`
- Create: `flutter-app/test/features/games/data/game_contract_parsing_test.dart`

- [x] Add JSON fixture tests matching the canonical backend responses from Task 1.
- [x] Confirm the tests expose these current defects:

```text
Matching request uses variation instead of variant.
Matching parser reads matches_column instead of definitions_column.
Grammar Quiz assumes correct_index instead of correct_answer.
Hangman expects fields the backend does not currently provide.
```

- [ ] Introduce a shared game envelope carrying `sessionId`, `gameType`, and `level` after Task 4 persists real sessions.
- [x] Make Matching use `variant` and `definitions_column`.
- [x] Remove or repair duplicate parsing code that assumes Matching columns contain maps when the API returns strings.
- [x] Make Grammar Quiz compare the selected option value with `correctAnswer`.
- [x] Parse Hangman `hints`, `base_xp`, and `max_lives` without silent gameplay-changing defaults.
- [x] Run:

```bash
cd flutter-app
flutter test test/features/games/data/game_contract_parsing_test.dart
flutter analyze lib/features/games test/features/games
```

Expected: tests pass and analyzer reports no issues.

- [ ] Commit:

```bash
git add flutter-app/lib/features/games flutter-app/test/features/games/data
git commit -m "fix: align Flutter game contracts with API"
```

## Chunk 2: Server-Authoritative Game Rewards

### Task 3: Implement Pure Game Scoring Rules

**Files:**

- Create: `backend-service/app/services/game_scoring_service.py`
- Create: `backend-service/tests/services/test_game_scoring_service.py`

- [x] Write parameterized tests for valid, invalid, zero-score, maximum-score, and tampered submissions.
- [x] Define explicit rules:

```text
Word Scramble: sum XP for verified correct words.
Fill Blank: sum XP for verified correct answers.
Matching: proportional XP for verified matched pairs; zero pairs means zero XP.
Spelling Bee: sum XP for verified words; partial credit only if explicitly specified.
Grammar Quiz: sum XP for verified correct answers.
Hangman: XP only on a verified win, minus bounded hint penalties, floored at zero.
```

- [x] Reject:

```text
negative counts
correct > total
submitted total different from session total
unknown question IDs
duplicate answer IDs
unknown game types
```

- [x] Implement a pure service returning:

```python
GameScore(
    correct_count=...,
    total_count=...,
    raw_xp=...,
    penalties=...,
    final_base_xp=...,
)
```

- [x] Run:

```bash
cd backend-service
DEBUG=false pytest tests/services/test_game_scoring_service.py -q
```

Expected: all scoring tests pass without database access.

- [ ] Commit:

```bash
git add backend-service/app/services/game_scoring_service.py backend-service/tests/services/test_game_scoring_service.py
git commit -m "feat: add server-side game scoring rules"
```

### Task 4: Persist And Complete Game Sessions

**Files:**

- Modify: `backend-service/app/models/games.py`
- Create: `backend-service/app/schemas/games.py`
- Create: `backend-service/app/crud/games.py`
- Modify: `backend-service/app/routes/games.py`
- Create: `backend-service/tests/routes/test_game_sessions.py`

- [x] Add tests proving each game GET creates a `GameSession` owned by the authenticated user.
- [x] Store in `session_data`:

```text
requested level
game variant
question/word identifiers
server answer snapshot
per-item XP values
configured question count
```

- [x] Return `session_id` with every game payload.
- [x] Add:

```http
POST /games/sessions/{session_id}/complete
```

Request shape:

```json
{
  "answers": [],
  "client_duration_seconds": 42,
  "hints_used": 0
}
```

Response shape:

```json
{
  "session_id": "...",
  "correct_count": 4,
  "total_count": 5,
  "xp_awarded": 48,
  "award_status": "awarded",
  "new_total_xp": 1200,
  "new_level": 8,
  "current_xp_in_level": 140,
  "xp_for_next_level": 240,
  "level_progress": 0.5833,
  "new_rank": "silver"
}
```

- [x] Derive elapsed time from server timestamps; treat client duration as telemetry only.
- [x] Reject another user's session, expired sessions, malformed answers, and return the persisted result for an already-completed session without re-awarding XP.
- [x] Lock the session row during completion using `SELECT ... FOR UPDATE`.
- [x] Set `completed_at` and `xp_awarded` in the same transaction as the XP mutation.
- [x] Run:

```bash
cd backend-service
DEBUG=false pytest tests/routes/test_game_sessions.py -q
```

Expected: valid completion succeeds; replay and ownership violations fail.

- [ ] Commit:

```bash
git add backend-service/app/models/games.py backend-service/app/schemas/games.py backend-service/app/crud/games.py backend-service/app/routes/games.py backend-service/tests/routes/test_game_sessions.py
git commit -m "feat: add idempotent game session completion"
```

### Task 5: Centralize XP Mutation And Idempotency

**Files:**

- Create: `backend-service/app/services/xp_service.py`
- Modify: `backend-service/app/routes/xp.py`
- Modify: `backend-service/app/models/xp.py`
- Modify: `backend-service/app/services/game_scoring_service.py`
- Modify: `backend-service/app/routes/games.py`
- Create: `backend-service/tests/services/test_xp_service.py`
- Create: `backend-service/tests/routes/test_xp_award_security.py`
- Create: `backend-service/alembic/versions/<revision>_add_xp_award_idempotency.py`

- [ ] Write tests for:

```text
daily cap
streak multiplier
level progress
rank recalculation
duplicate source/source_id
concurrent duplicate game completion
invalid source
client attempt to award game XP through /xp/award
```

- [ ] Extract one transactional XP service that updates:

```text
User total XP and level
XPTransaction
DailyActivity
UserRank
LeaderboardEntry
achievement progress
```

- [x] Make `/games/sessions/{id}/complete` call this service with the server-computed base XP.
- [x] Make generic `/xp/award` reject `source == "game"` and validate all allowed non-game sources.
- [ ] Require `source_id` for all repeat-sensitive sources.
- [x] Add a PostgreSQL partial unique index for non-null `(user_id, source, source_id)`.
- [x] Before writing the migration, run:

```bash
cd backend-service
alembic heads
```

Use the actual current head as `down_revision`; do not assume a revision ID.

- [x] Standardize daily calculations on UTC.
- [x] When the cap is reached, return the user's real current progress instead of zeros.
- [x] Run:

```bash
cd backend-service
DEBUG=false pytest tests/services/test_xp_service.py tests/routes/test_xp_award_security.py tests/routes/test_game_sessions.py -q
```

Expected: all tests pass, including replay protection.

- [ ] Commit:

```bash
git add backend-service/app backend-service/tests backend-service/alembic/versions
git commit -m "fix: make game XP transactional and server authoritative"
```

## Chunk 3: Rank, Leaderboard, And Achievement Consistency

### Task 6: Define One Leaderboard Ranking Policy

**Files:**

- Modify: `backend-service/app/crud/leaderboard.py`
- Modify: `backend-service/app/routes/gamification.py`
- Modify: `backend-service/app/routes/xp.py`
- Modify: `backend-service/app/services/xp_service.py`
- Create: `backend-service/tests/crud/test_leaderboard_ranking.py`

- [x] Choose competition ranking for ties:

```text
XP: 100, 100, 80
Rank: 1, 1, 3
```

- [x] Add tests showing list positions and the current user's rank agree.
- [x] Remove fallback behavior that reports lifetime `total_xp` as weekly `xp_earned`.
- [x] Ensure every XP award updates the correct weekly leaderboard entry.
- [x] Define endpoint roles:

```text
/gamification/leaderboard: canonical league leaderboard
/xp/leaderboard: overall weekly leaderboard, explicitly labeled overall
```

- [x] Implement reliable Redis invalidation after committed XP awards.
- [x] Run:

```bash
cd backend-service
DEBUG=false pytest tests/crud/test_leaderboard_ranking.py -q
```

- [ ] Commit:

```bash
git add backend-service/app/crud/leaderboard.py backend-service/app/routes/gamification.py backend-service/app/routes/xp.py backend-service/app/services/xp_service.py backend-service/tests/crud/test_leaderboard_ranking.py
git commit -m "fix: make leaderboard updates and tie ranks consistent"
```

### Task 7: Correct Rank Change And Demotion Logic

**Files:**

- Modify: `backend-service/app/services/rank_service.py`
- Modify: `backend-service/app/routes/gamification.py`
- Create: `backend-service/tests/services/test_rank_service.py`

- [x] Add tests for every tier threshold, CEFR contribution, level cap, invalid CEFR fallback, promotion, demotion, and unchanged rank.
- [x] Rename or replace `check_rank_up` with direction-aware rank change output:

```python
RankChange(
    changed=True,
    direction="promotion",  # promotion | demotion | unchanged
    old_rank="bronze",
    new_rank="silver",
)
```

- [x] Compute promotion and demotion zones from actual participant positions instead of returning hardcoded `false`.
- [x] Keep the existing 60% numeric-level and 40% CEFR formula unless a product requirement explicitly changes it.
- [x] Run:

```bash
cd backend-service
DEBUG=false pytest tests/services/test_rank_service.py -q
```

- [ ] Commit:

```bash
git add backend-service/app/services/rank_service.py backend-service/app/routes/gamification.py backend-service/tests/services/test_rank_service.py
git commit -m "fix: distinguish rank promotion and demotion"
```

### Task 8: Trigger Game Achievements After Completion

**Files:**

- Modify: `backend-service/app/services/xp_service.py`
- Modify: `backend-service/app/services/__init__.py`
- Create: `backend-service/tests/services/test_game_achievement_progress.py`

- [x] Add tests proving a completed game triggers relevant game-completion and streak achievement evaluation exactly once.
- [x] Trigger achievement evaluation after the game transaction succeeds.
- [x] Invalidate achievement and wallet caches only when their underlying data changes.
- [x] Ensure replayed sessions cannot advance achievement progress.
- [x] Run:

```bash
cd backend-service
DEBUG=false pytest tests/services/test_game_achievement_progress.py -q
```

- [ ] Commit:

```bash
git add backend-service/app/services backend-service/tests/services/test_game_achievement_progress.py
git commit -m "feat: connect game completion to achievements"
```

## Chunk 4: Flutter Session And Reward Flow

### Task 9: Submit Sessions Through Repository And Provider

**Files:**

- Modify: `flutter-app/lib/features/games/data/repositories/games_repository.dart`
- Modify: `flutter-app/lib/features/games/presentation/providers/games_provider.dart`
- Modify: `flutter-app/lib/features/gamification/domain/entities/xp_entities.dart`
- Modify: `flutter-app/lib/features/gamification/presentation/providers/xp_provider.dart`
- Create: `flutter-app/test/features/games/presentation/providers/games_provider_test.dart`

- [x] Add provider tests for successful completion, API failure, retry, and duplicate-submit prevention.
- [x] Store the server-issued `sessionId` with loaded game state.
- [x] Replace direct game calls to `/xp/award` with game session completion.
- [x] Model award state explicitly:

```dart
enum GameAwardStatus { idle, submitting, awarded, failed, alreadyAwarded }
```

- [x] Parse and apply the server's `current_xp_in_level`; do not reuse a stale profile value.
- [x] Preserve answer state while retrying a failed completion.
- [x] Disable repeated result submissions while a request is in flight.
- [x] Run:

```bash
cd flutter-app
flutter test test/features/games/presentation/providers/games_provider_test.dart
flutter analyze lib/features/games lib/features/gamification
```

- [ ] Commit:

```bash
git add flutter-app/lib/features/games flutter-app/lib/features/gamification flutter-app/test/features/games/presentation/providers
git commit -m "feat: complete game sessions from Flutter"
```

### Task 10: Correct Screen Result Submission

**Files:**

- Modify: `flutter-app/lib/features/games/presentation/screens/word_scramble_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/fill_blank_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/matching_game_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/spelling_bee_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/grammar_quiz_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/hangman_screen.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/game_result_screen.dart`
- Create: `flutter-app/test/features/games/presentation/screens/game_completion_test.dart`

- [ ] Add widget tests that finish every game and verify the submitted answer payload.
- [x] Remove client-computed XP as a displayed fallback.
- [x] Result behavior:

```text
Award succeeded: show exact server-awarded XP.
Award failed: show "XP not awarded" and a retry action.
Already awarded: show the original server result without resubmitting.
```

- [x] For delayed transitions, retain and cancel `Timer` instances in `dispose`, or guard callbacks with `mounted`.
- [x] Prevent navigation or setState calls after disposal.
- [ ] Run:

```bash
cd flutter-app
flutter test test/features/games/presentation/screens/game_completion_test.dart
```

- [ ] Commit:

```bash
git add flutter-app/lib/features/games/presentation/screens flutter-app/test/features/games/presentation/screens/game_completion_test.dart
git commit -m "fix: submit truthful results for every game"
```

### Task 11: Add Spelling Bee Pronunciation

**Files:**

- Create: `flutter-app/lib/features/games/data/services/game_pronunciation_service.dart`
- Modify: `flutter-app/lib/features/games/di/games_di.dart`
- Modify: `flutter-app/lib/features/games/presentation/screens/spelling_bee_screen.dart`
- Reuse: `flutter-app/lib/features/voice/data/datasources/voice_remote_datasource.dart`
- Create: `flutter-app/test/features/games/data/game_pronunciation_service_test.dart`

- [ ] Add tests for backend audio URL, AI TTS fallback, synthesis failure, and play-count handling.
- [ ] Prefer a supplied game `audio_url`.
- [ ] If absent, synthesize through the existing voice datasource and AI API client.
- [x] Decrement remaining plays only after audio begins successfully.
- [ ] Expose a retryable audio error without blocking the rest of the game.
- [ ] Run:

```bash
cd flutter-app
flutter test test/features/games/data/game_pronunciation_service_test.dart
flutter analyze lib/features/games
```

- [ ] Commit:

```bash
git add flutter-app/lib/features/games flutter-app/test/features/games/data/game_pronunciation_service_test.dart
git commit -m "feat: add reliable spelling bee pronunciation"
```

## Chunk 5: Error Handling And UI Quality

### Task 12: Replace Infinite Loading With Explicit States

**Files:**

- Create: `flutter-app/lib/features/games/presentation/widgets/game_load_state.dart`
- Modify: all six files under `flutter-app/lib/features/games/presentation/screens/`
- Reuse: `flutter-app/lib/core/widgets/error_widget.dart`
- Create: `flutter-app/test/features/games/presentation/screens/game_load_state_test.dart`

- [ ] Add widget tests for loading, loaded, empty payload, network error, malformed payload, and retry.
- [x] Stop using `_gameLoaded == false` as a permanent spinner condition after a failed request.
- [x] Render:

```text
initial/loading -> progress indicator
error -> localized message and retry button
empty -> localized empty state and retry/back action
ready -> game content
```

- [ ] Keep one load operation state per active screen so stale provider errors do not leak between games.
- [ ] Run:

```bash
cd flutter-app
flutter test test/features/games/presentation/screens/game_load_state_test.dart
```

- [ ] Commit:

```bash
git add flutter-app/lib/features/games/presentation flutter-app/test/features/games/presentation/screens/game_load_state_test.dart
git commit -m "fix: add retryable game loading states"
```

### Task 13: Accessibility, Reduced Motion, And Responsive Layout

**Files:**

- Modify: `flutter-app/lib/features/games/presentation/screens/games_hub_screen.dart`
- Modify: all game screens and shared game widgets
- Modify: `flutter-app/assets/i18n/en.json`
- Modify: `flutter-app/assets/i18n/vi.json`
- Create: `flutter-app/test/features/games/presentation/screens/game_accessibility_test.dart`

- [ ] Replace tap-only `GestureDetector` controls with semantic buttons, `InkWell`, or `Semantics(button: true)`.
- [ ] Give controls labels, selected/disabled state, and adequate touch targets.
- [ ] Add keyboard focus/activation for web and desktop where applicable.
- [ ] Respect `MediaQuery.disableAnimations` and accessible navigation settings for confetti and animated transitions.
- [ ] Ensure narrow screens do not overflow and wide screens do not stretch game content excessively.
- [ ] Use visible focus and sufficient contrast for correct, incorrect, selected, and disabled states.
- [ ] Localize every new status, error, retry, and award message in English and Vietnamese.
- [ ] Remove or hide the hardcoded daily challenge until it has a real persisted backend source; do not present demo state as user progress.
- [ ] Add semantics tests and layout tests at representative widths.
- [ ] Run:

```bash
cd flutter-app
flutter test test/features/games/presentation/screens/game_accessibility_test.dart
flutter analyze lib/features/games
```

- [ ] Commit:

```bash
git add flutter-app/lib/features/games flutter-app/assets/i18n flutter-app/test/features/games/presentation/screens/game_accessibility_test.dart
git commit -m "fix: improve game accessibility and responsive states"
```

## Chunk 6: Test Infrastructure And Release Verification

### Task 14: Make Backend Tests Self-Isolated

**Files:**

- Modify: `backend-service/tests/conftest.py`
- Modify: `backend-service/.env.test.example`
- Modify: `backend-service/README.md`
- Modify: `backend-service/Makefile` if present

- [ ] Set `DEBUG=false` before application settings are imported in tests.
- [ ] Require the configured test database name to end with `_test` before dropping or recreating schemas.
- [ ] Document creation and teardown of `lexilingo_test`.
- [ ] Add a repeatable test target that cannot point at production.
- [ ] Run:

```bash
cd backend-service
DEBUG=false pytest tests/services tests/routes tests/crud -q
```

Expected: no environment parsing error and no database setup error.

- [ ] Commit:

```bash
git add backend-service/tests/conftest.py backend-service/.env.test.example backend-service/README.md backend-service/Makefile
git commit -m "test: isolate backend game test environment"
```

### Task 15: Full Regression And Manual Acceptance

**Files:**

- Modify: `docs/Report/RPT-024_GAMES_ENGINE.md`
- Modify: `docs/Report/RPT-025_GAMIFICATION_XP_SYSTEM.md`
- Create: `docs/qa/game-system-acceptance.md`

- [ ] Run backend tests:

```bash
cd backend-service
DEBUG=false pytest -q
```

- [ ] Run Flutter tests and static analysis:

```bash
cd flutter-app
flutter test
flutter analyze
```

- [ ] Manually validate each game:

```text
load success
load failure and retry
correct answer
incorrect answer
zero-score completion
maximum-score completion
back navigation during delayed transition
completion request failure and retry
duplicate completion attempt
XP cap reached
rank promotion or demotion
leaderboard refresh
achievement progress
```

- [ ] Validate UI at narrow phone, standard phone, tablet/web width, and text scale 200%.
- [ ] Validate reduced motion, screen-reader labels, keyboard navigation, and audio failure.
- [ ] Verify database invariants directly:

```text
one completed GameSession
one XPTransaction per session
one leaderboard increment
one achievement increment
consistent User total_xp, level, and rank
```

- [ ] Update reports with the implemented API contract, scoring rules, rank formula, security model, and known limitations.
- [ ] Record all commands and results in `docs/qa/game-system-acceptance.md`.
- [ ] Commit:

```bash
git add docs/Report/RPT-024_GAMES_ENGINE.md docs/Report/RPT-025_GAMIFICATION_XP_SYSTEM.md docs/qa/game-system-acceptance.md
git commit -m "docs: record game system release verification"
```

## Recommended Execution Order

Execute tasks in numeric order. Tasks 6-8 may run in parallel only after Tasks 3-5 are merged. Tasks 10-13 may be split by screen after Task 9 establishes the provider and repository contract. Task 15 is the release gate and must not be skipped.

## Rollout Notes

- Deploy the migration and backend before releasing the new Flutter client.
- Keep temporary response aliases for one client release if older clients are active.
- Observe duplicate award rejection, completion error rate, XP distribution per game, and leaderboard write failures.
- Remove compatibility aliases after the minimum supported client uses canonical fields.
- If anomalies occur, disable game completion awards server-side while keeping practice gameplay available; do not restore client-authoritative XP.
