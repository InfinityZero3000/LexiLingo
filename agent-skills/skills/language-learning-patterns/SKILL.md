---
name: lexilingo-language-learning-patterns
description: Best practices for building interactive language learning features. Use when implementing spaced repetition, vocabulary exercises, pronunciation feedback, or adaptive learning algorithms. Triggers on tasks involving educational content generation, progress tracking, or learning path optimization.
license: MIT
metadata:
  author: LexiLingo Team
  version: "1.0.0"
---

# LexiLingo Language Learning Patterns

Comprehensive best practices for building effective language learning applications. Contains rules across multiple categories covering spaced repetition, content generation, progress tracking, and adaptive learning algorithms.

## When to Apply

Use this skill when:
- Implementing vocabulary exercises or flashcards
- Building spaced repetition systems (SRS)
- Generating language learning content
- Tracking learner progress and analytics
- Implementing adaptive difficulty systems
- Designing pronunciation feedback systems
- Creating gamified learning experiences

## Rule Categories by Priority

| Priority | Category              | Impact   | Prefix             |
| -------- | --------------------- | -------- | ------------------ |
| 1        | Spaced Repetition     | CRITICAL | `srs-`             |
| 2        | Content Generation    | HIGH     | `content-`         |
| 3        | Progress Tracking     | HIGH     | `progress-`        |
| 4        | Adaptive Learning     | HIGH     | `adaptive-`        |
| 5        | Pronunciation         | MEDIUM   | `pronunciation-`   |
| 6        | Gamification          | MEDIUM   | `gamification-`    |
| 7        | Accessibility         | MEDIUM   | `accessibility-`   |

## Quick Reference

### 1. Spaced Repetition (CRITICAL)

- `srs-sm2-algorithm` - Use SuperMemo-2 algorithm for optimal intervals
- `srs-ease-factor` - Adjust ease factor based on user performance
- `srs-review-timing` - Schedule reviews at optimal intervals
- `srs-lapse-handling` - Reset intervals properly on failed reviews

### 2. Content Generation (HIGH)

- `content-context-examples` - Provide contextual sentence examples
- `content-difficulty-levels` - Grade content by CEFR levels (A1-C2)
- `content-native-audio` - Use native speaker audio for pronunciation
- `content-cultural-context` - Include cultural notes and usage tips

### 3. Progress Tracking (HIGH)

- `progress-learning-streaks` - Track and motivate daily learning streaks
- `progress-xp-system` - Implement experience points for engagement
- `progress-milestone-celebration` - Celebrate achievements and milestones
- `progress-time-tracking` - Track time spent on different activities

### 4. Adaptive Learning (HIGH)

- `adaptive-difficulty-adjustment` - Dynamically adjust exercise difficulty
- `adaptive-weak-points` - Focus on learner's weak areas
- `adaptive-review-priority` - Prioritize words that need more practice
- `adaptive-learning-pace` - Adapt to individual learning speed

### 5. Pronunciation (MEDIUM)

- `pronunciation-phoneme-feedback` - Provide phoneme-level feedback
- `pronunciation-pitch-contour` - Analyze tone and intonation
- `pronunciation-visual-feedback` - Use visual aids for mouth position
- `pronunciation-recording-comparison` - Compare learner vs native speech

### 6. Gamification (MEDIUM)

- `gamification-achievement-badges` - Award badges for accomplishments
- `gamification-leaderboards` - Implement friendly competition
- `gamification-daily-goals` - Set and track daily learning goals
- `gamification-reward-consistency` - Reward consistent practice

### 7. Accessibility (MEDIUM)

- `accessibility-dyslexia-friendly` - Use dyslexia-friendly fonts and spacing
- `accessibility-keyboard-navigation` - Support full keyboard navigation
- `accessibility-screen-reader` - Ensure screen reader compatibility
- `accessibility-visual-impairment` - Support high contrast and large text

## How to Use

Read individual rule files for detailed explanations and code examples:

```
rules/srs-sm2-algorithm.md
rules/content-difficulty-levels.md
```

Each rule file contains:
- Brief explanation of why it matters
- Incorrect implementation example
- Correct implementation example
- Additional context and references

## Full Compiled Document

For the complete guide with all rules expanded: `AGENTS.md`

## Integration with LexiLingo

This skill integrates with:
- **Backend Service**: Progress tracking, SRS algorithms, user analytics
- **AI Service**: Content generation, pronunciation analysis, adaptive difficulty
- **Flutter App**: UI/UX patterns, gamification, accessibility features
- **DL Models**: Speech recognition, pronunciation scoring, content recommendations

## References

- [SuperMemo Algorithm](https://www.supermemo.com/en/archives1990-2015/english/ol/sm2)
- [CEFR Framework](https://www.coe.int/en/web/common-european-framework-reference-languages)
- [Duolingo Research](https://blog.duolingo.com/research/)
- [Anki SRS Documentation](https://faqs.ankiweb.net/what-spaced-repetition-algorithm.html)
