# Lesson Speaking STT Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record lesson speech, transcribe it with Faster-Whisper, and approve only sufficiently matching answers.

**Architecture:** Add a testable transcript matcher and a reusable lesson recording control backed by the existing `VoiceProvider`. Wire both speaking lesson variants to the control and add missing platform permission configuration.

**Tech Stack:** Flutter, Dart, Provider, record, Faster-Whisper HTTP API

---

## Chunk 1: Matching Logic

### Task 1: Transcript matcher

**Files:**
- Create: `flutter-app/lib/features/learning/domain/services/speaking_answer_matcher.dart`
- Create: `flutter-app/test/features/learning/speaking_answer_matcher_test.dart`

- [ ] Write tests for normalization and similarity thresholds.
- [ ] Run the focused test and confirm it fails.
- [ ] Implement token-aware edit-distance matching with a default 0.85 threshold.
- [ ] Run the focused test and confirm it passes.

## Chunk 2: Recording Control

### Task 2: Reusable microphone widget

**Files:**
- Create: `flutter-app/lib/features/learning/presentation/widgets/lesson_speaking_recorder.dart`
- Create: `flutter-app/test/features/learning/lesson_speaking_recorder_test.dart`

- [ ] Write widget tests using injected start/stop/transcribe functions.
- [ ] Implement idle, recording, processing, rejected, and approved states.
- [ ] Read Web blob URLs and native files into audio bytes.
- [ ] Submit only approved transcripts through the supplied callback.
- [ ] Run widget tests.

## Chunk 3: Integration And Permissions

### Task 3: Wire lesson exercises

**Files:**
- Modify: `flutter-app/lib/features/learning/presentation/widgets/premium_exercise_widgets.dart`
- Modify: `flutter-app/android/app/src/main/AndroidManifest.xml`
- Modify: `backend-service/app/routes/learning.py`
- Modify: `backend-service/tests/test_learning_routes.py`

- [ ] Replace both decorative microphone controls with the reusable recorder.
- [ ] Add Android microphone permission.
- [ ] Make backend lesson validation use the same threshold for speaking UI types.
- [ ] Add focused backend matcher tests.
- [ ] Format changed Dart files.
- [ ] Run all focused learning tests.
- [ ] Run `flutter analyze`.
- [ ] Review the final diff for unrelated changes.
