---
name: pipeline-conversation-scoring
description: Extract proficiency scores from every AI conversation turn using the GraphCAG pipeline. Every user message processed by the diagnosis node produces fluency_score, grammar_score, and vocabulary_level that must be persisted.
impact: CRITICAL
---

# Conversation-Based Proficiency Scoring Pipeline

## Context

The LexiLingo AI service uses a Graph-CAG pipeline to process user messages. The diagnosis node (`nodes_v2.py`) already produces per-turn scores:
- `fluency_score` (0.0-1.0)
- `grammar_score` (0.0-1.0)  
- `vocabulary_level` (A1-C2)
- `grammar_errors[]`

These scores are returned in the API response but **not systematically persisted** to the backend proficiency tables. This rule ensures every conversation turn updates the user's proficiency profile.

## Rule

### Score Extraction Flow

```
User Message
    ↓
GraphCAG Pipeline (diagnose node)
    ↓ produces: fluency_score, grammar_score, vocabulary_level, errors[]
    ↓
LoggingService.log_interaction()  ← Already exists (MongoDB)
    ↓
[NEW] ProficiencyUpdateService.update_from_conversation()
    ↓ maps scores to 5 display dimensions
    ↓
Backend API: POST /proficiency/record-from-ai
    ↓ updates user_proficiency_profiles + user_skill_scores
    ↓
Updated ProficiencyProfile returned to client
```

### Score Mapping: Pipeline → 5 Dimensions

| Display Dimension | Source Scores | Weight Formula |
|------------------|---------------|----------------|
| **Pronunciation** | `speaking.score` + phoneme analysis | Direct from pronunciation exercises |
| **Vocabulary** | `vocabulary_level` + word diversity | `vocab_score * 0.7 + word_range * 0.3` |
| **Fluency** | `fluency_score` from diagnosis | Direct from GraphCAG diagnosis |
| **Grammar** | `grammar_score` from diagnosis | Direct from GraphCAG diagnosis |
| **Intonation** | `speaking.score` + prosody analysis | Requires speech analysis (future) |

### Aggregation Strategy

Use **Exponential Moving Average (EMA)** to update skill scores:

```python
alpha = 0.3  # Weight for new observation
new_score = alpha * current_turn_score + (1 - alpha) * previous_skill_score
```

This ensures:
- Recent performance has higher weight
- Single bad interactions don't crash scores
- Gradual improvement is visible over time
- Difficulty multiplier adjusts alpha (harder exercises = higher alpha)

## Correct Implementation

```python
# In GraphCAG generate node or post-processing
async def update_proficiency_from_conversation(
    user_id: str,
    fluency_score: float,
    grammar_score: float,
    vocabulary_level: str,
    errors: list[dict],
) -> None:
    """Update user proficiency after each AI conversation turn."""
    
    # Map to exercise results format
    exercises = []
    
    if fluency_score > 0:
        exercises.append({
            "exercise_type": "conversation",
            "skill": "speaking",
            "difficulty_level": vocabulary_level,
            "is_correct": fluency_score >= 0.6,
            "score": fluency_score,
            "time_spent_seconds": 0,
        })
    
    if grammar_score > 0:
        exercises.append({
            "exercise_type": "conversation",
            "skill": "grammar",
            "difficulty_level": vocabulary_level,
            "is_correct": grammar_score >= 0.6 and len(errors) < 3,
            "score": grammar_score,
            "time_spent_seconds": 0,
        })
    
    # Send to backend
    await backend_client.post(
        f"/proficiency/record-exercises",
        json={"results": exercises},
        headers={"Authorization": f"Bearer {user_token}"},
    )
```

## Incorrect Implementation

```python
# Anti-pattern: Only logging, not updating proficiency
async def process_message(state):
    # ... diagnosis produces scores ...
    await logging_service.log_interaction(...)  # MongoDB only
    return {"response": tutor_response}
    # ❌ Scores are lost! Never reach backend proficiency tables

# Anti-pattern: Updating on every single keystroke
# Only update after a complete conversation turn
```

## Known Gaps in Current System

1. **G1**: AI `AssessmentService` writes to MongoDB, backend `ProficiencyService` writes to PostgreSQL — no sync
2. **G3**: GraphCAG scores not persisted to backend
3. **G7**: Speaking/Writing skills have no exercise input path
4. **G6**: `consistency_score` hardcoded to 0.8
