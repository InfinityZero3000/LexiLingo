# Vocabulary Speaking Practice Checklist

Source plan: `docs/ Plan_Vocabulary Speak.md`

## Scope

- [x] Add FSRS columns to `user_vocabulary` with backward-compatible defaults.
- [x] Expose FSRS fields from backend models and response schemas.
- [x] Update vocabulary review submission to calculate SM-2 and FSRS in parallel.
- [x] Add backend pronunciation evaluation endpoint under `/api/v1/vocabulary/pronunciation/evaluate`.
- [x] Add AI service HuBERT pronunciation endpoint under `/api/v1/stt/assess-pronunciation`.
- [x] Forward pronunciation audio from backend to AI service with the user's authorization header.
- [x] Map pronunciation score to speaking feedback:
  - [x] `score >= 80`: 3 stars, `Amazing`, quality `5`.
  - [x] `60 <= score < 80`: 2 stars, `Good`, quality `3`.
  - [x] `score < 60`: 1 star, `Try again`, quality `1`.
- [x] Add Flutter API model and repository method for pronunciation evaluation.
- [x] Build Flutter vocabulary speaking practice screen with record, evaluate, replay, retry, and submit controls.
- [x] Add navigation from flashcard review to speaking practice mode.
- [x] Run backend tests for vocabulary/FSRS.
- [x] Run AI service tests for pronunciation route.
- [x] Run Flutter static analysis.
- [x] Run Flutter model test for pronunciation evaluation mapping.

## Implementation Order

- [x] Backend database migration and SQLAlchemy model fields.
- [x] Backend FSRS calculation and schema exposure.
- [x] Backend pronunciation proxy route.
- [x] AI pronunciation route and router registration.
- [x] Flutter data/domain API wiring.
- [x] Flutter speaking practice UI and navigation.
- [x] Verification pass and checklist status update.

## Next Plan: FSRS Reminder Scheduler

Plan: `docs/superpowers/plans/2026-06-01-fsrs-reminder-scheduler.md`

- [ ] Add backend reminder preferences and delivery audit tables.
- [ ] Add user-configurable reminder settings API.
- [ ] Add persisted notification API.
- [ ] Add FSRS due-count scheduler adapter based on `next_review_date`.
- [ ] Add FCM push service for vocabulary review reminders.
- [ ] Add vocabulary review reminder email service and templates.
- [ ] Add Celery worker and beat process configuration.
- [ ] Sync Flutter Settings reminder controls with backend.
- [ ] Route reminder notification taps to vocabulary review.
- [ ] Verify backend, Flutter, worker dry-run, and production rollout safety.
