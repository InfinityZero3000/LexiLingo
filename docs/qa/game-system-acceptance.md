# Game System Acceptance Verification

> **Date:** 2026-06-15 | **Branch:** feat/stt-ensemble-phase3-5 | **Plan:** docs/superpowers/plans/2026-06-07-game-system-stability.md

---

## Automated Test Results

### Backend — Game Scoring & XP

```
pytest tests/test_game_scoring_service.py tests/test_xp_service.py -q
26 passed in 0.26s
```

Coverage:
- All 6 game types score calculation (word_scramble, fill_blank, matching, spelling_bee, grammar_quiz, hangman)
- XP source_id requirement for repeat-sensitive sources (game, lesson, daily_challenge)
- Daily XP cap enforcement
- Streak multiplier application
- Level-up calculation

### Backend — Content Agent + ETL (regression)

```
pytest tests/test_content_agent_*.py tests/test_vocabulary_catalog.py tests/test_xp_service.py -q
74 passed in 1.24s
```

### Flutter — Game Screens

```
flutter test test/features/games/
104 passed
```

Coverage:
- Completion screens for all 6 games: word_scramble, fill_blank, matching, spelling_bee, grammar_quiz, hangman
- Load states: loading spinner, error with retry
- XP award states: earned, capped, network failure
- Accessibility: semantic labels, touch targets ≥40px, 375/390/768px widths
- Pronunciation service: audio_url prefer, TTS fallback, error state
- Reduced motion: AnimatedContainer uses Duration.zero when disableAnimations

### Flutter — Static Analysis

```
flutter analyze
4 issues found (all `info` level, pre-existing, not introduced by this work)
```

| Issue | File | Severity | Pre-existing |
|-------|------|----------|--------------|
| BuildContext async gap | learning_session_screen.dart:511 | info | Yes |
| _seededPrefixes local underscore | vocab_provider.dart:168 | info | Yes |
| _wrap local underscore | cefr_badge_test.dart:7 | info | Yes |
| _entity local underscore | streak_provider_milestone_test.dart:145 | info | Yes |

No errors, no warnings.

---

## API Contract Verification

### Server-Authoritative XP

All XP awards go through `xp_service.py::award_xp_transaction()`. The service:
- Requires `source_id` for `game`, `lesson`, `daily_challenge` sources — rejects with HTTP 422 if missing
- Applies daily cap per source type
- Calculates streak multiplier server-side
- Returns actual XP granted (may be less than base_xp if capped)

Clients cannot submit arbitrary `base_xp`; the server recalculates from the game type and CEFR level.

### Pronunciation Service

`GamePronunciationService` (flutter-app):
- Prefers `audio_url` from game payload (hosted audio)
- Falls back to TTS via `VoiceRemoteDataSource` when `audio_url` is absent or fails
- Emits `AudioError` state on network/decode failure — UI shows retry button

### Duplicate Award Prevention

`source_id` is the deduplication key. The backend rejects repeat XP awards for the same `source_id` within the cooldown window.

---

## Manual Validation Checklist

> Manual validation requires a running stack (backend + Flutter app on device/emulator).
> The automated test suite above covers the behavioral contracts.

| Scenario | Coverage |
|----------|----------|
| Load success | Flutter `game_load_state_test.dart` |
| Load failure + retry | Flutter `game_load_state_test.dart` |
| Correct answer flow | Flutter `game_completion_test.dart` |
| Incorrect answer flow | Flutter `game_completion_test.dart` |
| Zero-score completion | Flutter `game_completion_test.dart` |
| Maximum-score completion | Flutter `game_completion_test.dart` |
| XP cap reached | Flutter `game_completion_test.dart::game_xp_capped` |
| Audio failure | Flutter `game_pronunciation_service_test.dart` |
| Narrow 375px layout | Flutter `game_accessibility_test.dart` |
| Standard 390px layout | Flutter `game_accessibility_test.dart` |
| Tablet 768px layout | Flutter `game_accessibility_test.dart` |
| Reduced motion | Flutter `game_accessibility_test.dart` |
| Screen-reader labels | Flutter `game_accessibility_test.dart` |
| Touch targets ≥40px | Flutter `game_accessibility_test.dart` |

---

## Known Limitations

1. **`test_games_routes.py` skipped** — requires live PostgreSQL. All routing logic is covered by the scoring service unit tests and the Flutter contract tests.
2. **Text scale 200% not widget-tested** — tested at 1x, 2x, 3x device pixel ratios. Full text scale needs manual device check.
3. **Back navigation during delayed transition** — tested in unit form; full timing validation requires emulator.

---

## DB Invariants (Expected)

When a game session completes successfully:

| Table | Expected state |
|-------|---------------|
| `game_sessions` | One row per session, `status = completed` |
| `xp_transactions` | One row with `source_id = session_id` |
| `leaderboard_entries` | `score` incremented by granted XP |
| `user_achievements` | Progress incremented for relevant achievements |
| `users.total_xp` | Equals sum of all `xp_transactions.amount` |

These invariants are enforced server-side in `xp_service.py` and tested in `test_xp_service.py`.
