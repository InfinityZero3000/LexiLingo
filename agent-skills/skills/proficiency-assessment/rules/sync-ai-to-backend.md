---
name: sync-ai-to-backend
description: Synchronize proficiency assessment data from AI service (MongoDB) to backend service (PostgreSQL). Bridges the known gap where both services maintain separate assessment records.
impact: HIGH
---

# AI-to-Backend Proficiency Data Sync

## Context

**Known Gap G1**: The AI service `AssessmentService` writes to MongoDB (`user_assessments`), while the backend `ProficiencyService` writes to PostgreSQL (`user_proficiency_profiles`). These two systems don't sync, leading to stale or missing proficiency data.

## Rule

### Sync Architecture

```
AI Service (MongoDB)                    Backend Service (PostgreSQL)
├── ai_interactions (per-turn)    →     exercise_attempts
├── user_assessments (periodic)   →     user_proficiency_profiles
├── level_history (events)        →     user_level_history
└── LearnerProfileCache (Redis)         user_skill_scores
```

### Sync Strategy: Push After Assessment

After the AI `AssessmentService.assess_user()` completes, push results to backend:

```python
# In AI service, after assessment completes
async def sync_assessment_to_backend(
    user_id: str,
    assessment: LevelAssessment,
    backend_url: str = "http://localhost:8000",
) -> None:
    """Push AI assessment results to backend proficiency tables."""
    
    payload = {
        "assessed_level": assessment.level,
        "overall_score": assessment.overall_score,
        "skills": {
            "vocabulary": assessment.metrics.vocabulary_score,
            "grammar": assessment.metrics.grammar_score,
            "speaking": assessment.metrics.fluency_score,
            "listening": assessment.metrics.consistency_score,
            "reading": assessment.metrics.vocabulary_score * 0.8,
            "writing": assessment.metrics.grammar_score * 0.7,
        },
        "confidence": assessment.confidence,
        "source": "ai_assessment",
    }
    
    async with httpx.AsyncClient() as client:
        await client.post(
            f"{backend_url}/proficiency/sync-from-ai",
            json=payload,
            headers={"X-Internal-Key": INTERNAL_API_KEY},
        )
```

### New Backend Endpoint

```python
@router.post("/proficiency/sync-from-ai")
async def sync_from_ai(
    data: AISyncPayload,
    db: AsyncSession = Depends(get_db),
    api_key: str = Depends(verify_internal_key),
):
    """Receive proficiency data from AI service."""
    await proficiency_service.update_from_ai_assessment(
        db=db,
        user_id=data.user_id,
        assessed_level=data.assessed_level,
        skills=data.skills,
        confidence=data.confidence,
    )
```

### Conflict Resolution

When both AI and backend have scores for the same skill:
1. **Higher confidence wins**: If AI confidence > backend confidence, use AI scores
2. **Recency bias**: If timestamps differ by >24h, use the newer one
3. **Weighted merge**: `merged = ai_score * ai_confidence + backend_score * backend_confidence) / (ai_confidence + backend_confidence)`

### Frequency

- **Per-conversation sync**: Not needed (too expensive)
- **After AI assessment**: Sync immediately (triggered by `assess_user()`)
- **Periodic batch**: Every 6 hours, reconcile any drift
- **On profile view**: If last sync > 1 hour ago, trigger background sync
