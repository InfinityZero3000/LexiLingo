# Implementation Plan - Vocabulary Speaking Practice & FSRS Spaced Repetition

This plan details the implementation of a new Vocabulary Speaking Practice feature for LexiLingo. It covers adding FSRS algorithm support in the database and backend, exposing the HuBERT pronunciation evaluation model in the AI service, and building a premium Flutter speaking practice interface.

## User Review Required

> [!IMPORTANT]
> **FSRS Column Addition**: We will add 8 new columns to the `user_vocabulary` table to support the FSRS algorithm. The existing `next_review_date` and `last_reviewed_at` fields will be shared by both algorithms, maintaining 100% backward compatibility with existing queries.
> **FSRS Rating Mapping**: In the speaking practice flow, the quality score (0-5) will be mapped from the pronunciation stars:
> - 3 Stars (Amazing / score >= 80) -> Quality 5 (Easy / Perfect)
> - 2 Stars (Good / 60 <= score < 80) -> Quality 3 (Good)
> - 1 Star (Try again / score < 60) -> Quality 1 (Incorrect)

## Open Questions

> [!NOTE]
> None. The requirements and design are fully specified by the user request and mockup image.

---

## Proposed Changes

### Database & Backend Components

#### [NEW] [add_fsrs_and_speaking_fields.py](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/alembic/versions/add_fsrs_and_speaking_fields.py)
- Create a new Alembic migration to add the following columns to `user_vocabulary`:
  - `fsrs_stability` (Float, default 0.0, nullable=True)
  - `fsrs_difficulty` (Float, default 0.0, nullable=True)
  - `fsrs_elapsed_days` (Integer, default=0, nullable=True)
  - `fsrs_scheduled_days` (Integer, default=0, nullable=True)
  - `fsrs_reps` (Integer, default=0, nullable=True)
  - `fsrs_lapses` (Integer, default=0, nullable=True)
  - `fsrs_state` (Integer, default=0, nullable=True)
  - `fsrs_last_review` (DateTime, nullable=True)

#### [MODIFY] [vocabulary.py (model)](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/models/vocabulary.py)
- Update the `UserVocabulary` class to declare the new FSRS fields.

#### [MODIFY] [vocabulary.py (schema)](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/schemas/vocabulary.py)
- Add FSRS fields to `UserVocabularyResponse`.
- Add a new schema `PronunciationEvaluationResponse` returning score, stars, feedback label, transcription, and errors list.

#### [MODIFY] [vocabulary.py (crud)](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/crud/vocabulary.py)
- Update the `submit_review` function to calculate and update FSRS fields alongside SM-2 fields.
- Implement the FSRS scheduling formulas:
  - If reps = 0: Initialize stability and difficulty based on the rating.
  - Else: Calculate retrievability, update difficulty and stability, reset or increase repetitions/lapses, and set the next interval.
  - Set `next_review_date = now + timedelta(days=interval)`.

#### [MODIFY] [vocabulary.py (route)](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/backend-service/app/routes/vocabulary.py)
- Add a new route `POST /api/v1/vocabulary/pronunciation/evaluate`:
  - Accepts `audio` (UploadFile) and `vocabulary_id` (UUID).
  - Fetches the vocabulary word.
  - Forwards the audio file and target word to the `ai-service`.
  - Maps the evaluation score to stars and feedback ("Amazing" / "Good" / "Try again") and returns the result.

---

### AI Service Components

#### [NEW] [pronunciation.py (route)](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/ai-service/api/routes/pronunciation.py)
- Add a route `POST /api/v1/stt/assess-pronunciation`:
  - Accepts `audio` file and `target_text` parameter.
  - Decodes the uploaded audio to a float32 16kHz numpy array using `faster_whisper.audio.decode_audio` or scipy.
  - Runs `HuBERTService` to evaluate pronunciation.
  - Returns `overall_score`, `phoneme_scores`, and detailed phoneme errors/suggestions.

#### [MODIFY] [main.py](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/ai-service/api/main.py)
- Register the new pronunciation router.

---

### Flutter App (Frontend)

#### [NEW] [vocabulary_speaking_practice_screen.dart](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/flutter-app/lib/features/vocabulary/presentation/screens/vocabulary_speaking_practice_screen.dart)
- Build a premium UI matching the user's mockup:
  - App bar: title `< Lesson 1 Speaking practice` with macOS/Windows style close, maximize, and minimize action controls on the right.
  - Normal speed & Turtle speed (slow) speaker buttons on the top left.
  - Progress bar: green bar displaying progress (e.g. `No. 11 [=======] 11 in total`).
  - Target word in large green font, e.g. "religion", IPA "/rɪˈlɪdʒən/", and a "Meaning" button.
  - Interactive recording: Record user's pronunciation using `record` package with wave animations.
  - Bottom panel containing:
    - Quality text: e.g. "Amazing" / "Good" / "Try again".
    - Play button: "My pronunciation" (plays user's recorded audio using `just_audio`).
    - Stars: 1-3 yellow stars.
    - Buttons: "Try again" (light outline button) and "Submit" (solid green button).
  - Connect to backend:
    - Call evaluation API upon finishing recording.
    - Call review submission API when clicking "Submit" to save the spaced repetition data.

#### [MODIFY] [flashcard_review_screen.dart](file:///Users/nguyenhuuthang/Documents/RepoGitHub/LexiLingo/flutter-app/lib/features/vocabulary/presentation/screens/flashcard_review_screen.dart)
- Provide a navigation entry or option to switch to Speaking Practice Mode.

---

## Verification Plan

### Automated Tests
- Run backend unit tests to verify FSRS scheduling formulas:
  `pytest backend-service/tests`
- Run AI service test cases to verify HuBERT pronunciation evaluation:
  `pytest ai-service/tests`

### Manual Verification
- Launch backend and AI services.
- Test the new Speaking Practice screen on the iOS/Android simulator:
  - Check speaking practice page layout and alignment with mockup.
  - Click audio/speaker buttons to hear reference pronunciation.
  - Press record button, speak, verify that it uploads and displays correct pronunciation score (stars, text feedback, phonemes).
  - Press "My pronunciation" to replay own voice.
  - Click "Submit", verify database successfully updates FSRS properties (`fsrs_stability`, `fsrs_reps`etc.).
