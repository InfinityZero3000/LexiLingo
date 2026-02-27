---
name: lexilingo-proficiency-assessment
description: AI-driven multi-dimensional proficiency assessment for language learners. Use when implementing conversation-based skill evaluation, mapping AI scores to proficiency dimensions, syncing assessments between AI and backend services, or building proficiency visualization features.
license: MIT
metadata:
  author: LexiLingo Team
  version: "1.0.0"
---

# Proficiency Assessment Patterns

Comprehensive patterns for building AI-driven, multi-dimensional language proficiency assessment systems that evaluate learners through natural conversation and structured exercises.

## When to Apply

Use this skill when:
- Implementing AI-based proficiency scoring from conversations
- Mapping GraphCAG pipeline scores to proficiency dimensions
- Syncing assessment data between AI service (MongoDB) and backend (PostgreSQL)
- Building proficiency visualization (radar charts, score cards)
- Designing level-up mechanics based on demonstrated skill
- Creating confidence thresholds for score reliability
- Implementing the conversation → score → profile update pipeline

## Rule Categories by Priority

| Priority | Category                | Impact   | Prefix         |
| -------- | ----------------------- | -------- | -------------- |
| 1        | Score Pipeline          | CRITICAL | `pipeline-`    |
| 2        | Dimension Mapping       | CRITICAL | `dimension-`   |
| 3        | Confidence & Thresholds | HIGH     | `confidence-`  |
| 4        | Data Sync               | HIGH     | `sync-`        |
| 5        | Unlock & Display        | MEDIUM   | `display-`     |

## Quick Reference

### 1. Score Pipeline (CRITICAL)

- `pipeline-conversation-scoring` - Extract scores from every AI conversation turn
- `pipeline-aggregation` - Aggregate per-turn scores into session summaries
- `pipeline-ema-update` - Use Exponential Moving Average for skill score updates

### 2. Dimension Mapping (CRITICAL)

- `dimension-five-axis` - Map 6 backend skills to 5 display dimensions
- `dimension-weights` - Apply appropriate weights per dimension
- `dimension-cefr-alignment` - Align scores with CEFR level descriptors

### 3. Confidence & Thresholds (HIGH)

- `confidence-minimum-interactions` - Require 15+ interactions before showing scores
- `confidence-decay` - Decay confidence when user is inactive
- `confidence-per-skill` - Track confidence independently per skill

### 4. Data Sync (HIGH)

- `sync-ai-to-backend` - Sync AI service assessments to backend PostgreSQL
- `sync-idempotent` - Ensure sync operations are idempotent
- `sync-conflict-resolution` - Handle conflicting scores from different sources

### 5. Unlock & Display (MEDIUM)

- `display-unlock-threshold` - Show "--" until confidence threshold met
- `display-trend-indicators` - Show improving/declining/stable trends
- `display-recommendations` - Surface actionable skill improvement suggestions
