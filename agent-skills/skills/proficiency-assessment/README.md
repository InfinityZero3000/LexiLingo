# Proficiency Assessment Patterns

## Overview

AI-driven multi-dimensional proficiency assessment for language learners. Defines the pipeline from conversation analysis to persistent proficiency profiles.

## Architecture

```
User Chat/Exercise → GraphCAG Pipeline → Per-turn Scores
                                            ↓
                                    LoggingService (MongoDB)
                                            ↓
                                    AssessmentService (periodic)
                                            ↓
                                    Backend Sync (PostgreSQL)
                                            ↓
                                    Proficiency Profile API
                                            ↓
                                    Flutter Radar Chart UI
```

## Key Rules

- `pipeline-conversation-scoring.md` — Extract scores from every AI conversation turn
- `dimension-five-axis.md` — Map 6 backend skills → 5 display dimensions
- `confidence-minimum-interactions.md` — Require 15+ interactions before showing scores
- `sync-ai-to-backend.md` — Bridge the AI ↔ Backend proficiency data gap

## Known System Gaps

| Gap | Description | Impact |
|-----|------------|--------|
| G1 | AI writes MongoDB, backend writes PostgreSQL — no sync | CRITICAL |
| G3 | GraphCAG scores not persisted to backend | HIGH |
| G7 | Speaking/Writing skills have no exercise input path | MEDIUM |
