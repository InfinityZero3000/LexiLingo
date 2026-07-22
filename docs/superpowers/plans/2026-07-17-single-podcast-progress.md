# Single Podcast Progress Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show one playback progress bar in the podcast player.

**Architecture:** Keep progress rendering in `AudioPlayerControls`, where it is grouped with playback time and actions. Remove duplicate and misleading decoration only.

**Tech Stack:** Flutter, Dart

---

### Task 1: Remove duplicated playback UI

**Files:**
- Modify: `flutter-app/lib/features/podcast/presentation/screens/podcast_player_screen.dart`
- Modify: `flutter-app/lib/features/podcast/presentation/widgets/audio_player_controls.dart`

- [x] Remove the page-level progress bar and time labels.
- [x] Remove the inline card's decorative drag handle.
- [x] Format both files.
- [x] Run `flutter analyze`.
