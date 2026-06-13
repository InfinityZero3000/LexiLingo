# Lesson Speaking STT Design

## Goal

Make lesson microphone exercises record the learner, transcribe the recording
with the existing Faster-Whisper endpoint, and approve the answer only when the
transcript sufficiently matches the target sentence.

## Architecture

- Reuse the existing `record` package and `VoiceProvider` STT pipeline.
- Extract transcript comparison into a small learning utility so it can be
  tested independently of recording and network behavior.
- Replace the decorative microphone controls in `speaking_repeat` and
  `pronunciation_practice` with one reusable stateful recording control.
- Keep pronunciation approval based on transcript content. HuBERT phoneme
  scoring remains available elsewhere and is not required for this lesson flow.

## Recording Flow

1. The first tap requests microphone permission and starts WAV recording.
2. The second tap stops recording and reads the resulting audio bytes.
3. The control sends the bytes to `POST /api/v1/stt/transcribe` through
   `VoiceProvider`, including the existing backend JWT.
4. The returned transcript is normalized and compared with the target.
5. A similarity score of at least 0.85 approves the answer and submits the
   transcript. Lower scores display feedback and leave the exercise retryable.
6. The learning backend recognizes speaking UI types and applies the same
   normalization and 0.85 similarity threshold when recording lesson progress.

## UI States

- `idle`: blue microphone and prompt to start.
- `recording`: highlighted stop control, elapsed time, and recording label.
- `processing`: disabled control and progress indicator.
- `rejected`: transcript and similarity feedback with retry prompt.
- `approved`: transcript and success feedback while lesson submission finishes.

## Error Handling

- Permission denial, unreadable audio, empty transcription, and STT/network
  failures show an actionable message without submitting the exercise.
- Recording resources and timers are stopped and disposed with the widget.
- Android declares `RECORD_AUDIO`. Web permission continues to be requested by
  `record_web` from the user gesture.

## Testing

- Unit tests cover punctuation/case normalization, exact matches, near matches,
  and clearly incorrect transcripts.
- Backend tests cover matching and rejected speaking transcripts.
- Widget tests cover microphone state transitions with injectable recording and
  transcription callbacks, avoiding real hardware and network access.
- Run focused Flutter tests and `flutter analyze`.
