---
name: lexilingo-flutter-ui-animations
description: Animation patterns for LexiLingo Flutter app. Use when implementing shimmer loading skeletons, staggered list entry animations, Hero course-card transitions, pull-to-refresh, and the Level-Up celebration dialog. Ensures smooth 60fps performance on mid-range devices.
license: MIT
metadata:
  author: LexiLingo Team
  version: "1.0.0"
---

# Flutter UI Animations for LexiLingo

All animations must enhance cognition and delight — not slow the user down. Default to implicit animations (`AnimatedContainer`, `AnimatedOpacity`) and upgrade to explicit only when needed.

## When to Apply

Use this skill when:
- Adding shimmer skeletons to Home, Profile, Course List screens
- Implementing staggered entry for card lists (Home page, Notifications)
- Building Hero transitions between course card and detail screen
- Creating the Level-Up celebration dialog (XP reward feedback)
- Adding pull-to-refresh with custom bounce animation

## Rule Categories by Priority

| Priority | Category          | Impact   | Prefix      |
|----------|-------------------|----------|-------------|
| 1        | Loading States    | HIGH     | `loading-`  |
| 2        | List Animation    | HIGH     | `list-`     |
| 3        | Navigation        | HIGH     | `nav-`      |
| 4        | Celebration       | MEDIUM   | `celebrate-`|
| 5        | Performance       | HIGH     | `perf-`     |

## Quick Reference

### 1. Loading States (HIGH)
- `loading-shimmer` — Shimmer skeleton for cards and lists using the `shimmer` package

### 2. List Animation (HIGH)
- `list-staggered-entry` — Staggered FadeSlide-in for list items on first load

### 3. Navigation (HIGH)
- `nav-hero-course-card` — Hero tag pattern for smooth course card → detail transition

### 4. Celebration (MEDIUM)
- `celebrate-level-up-dialog` — Level-Up full-screen overlay with scale + confetti

### 5. Performance (HIGH)
- `perf-animation-best-practices` — RepaintBoundary, avoid rebuilds in AnimatedBuilder
