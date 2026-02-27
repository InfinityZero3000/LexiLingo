# LexiLingo Team - Proficiency Assessment Patterns

**Version 1.0.0**  
LexiLingo Team  
February 2026

> **Note:**  
> This document is for agents and LLMs to follow when implementing or maintaining  
> the proficiency assessment system. Optimized for AI-assisted workflows.

---

## Abstract

Patterns for AI-driven multi-dimensional proficiency assessment in language learning applications. Covers conversation-based scoring, skill dimension mapping, confidence thresholds, and the flow from AI analysis to persistent proficiency profiles.

---

## Table of Contents

1. [Score Pipeline](#1-score-pipeline)
2. [Dimension Mapping](#2-dimension-mapping)
3. [Confidence & Thresholds](#3-confidence--thresholds)
4. [Data Sync](#4-data-sync)

---

## 1. Score Pipeline

**Impact: CRITICAL**

### 1.1 Conversation-Based Proficiency Scoring

Every AI conversation turn produces scores that must flow through to the proficiency system.

**Pipeline Flow:**

```
User Message → GraphCAG diagnose → {fluency_score, grammar_score, vocabulary_level, errors[]}
                    ↓
            LoggingService (MongoDB ai_interactions)
                    ↓
            [NEW] ProficiencyUpdateService
                    ↓
            Backend POST /proficiency/record-exercises
                    ↓
            PostgreSQL user_skill_scores updated via EMA
```

**Aggregation: Exponential Moving Average**

```python
alpha = 0.3  # Weight for new observation
new_score = alpha * current_turn_score + (1 - alpha) * previous_skill_score
```

**Difficulty multiplier adjusts alpha:**

| Difficulty | Alpha Multiplier |
|-----------|-----------------|
| A1 | 0.5x (lower impact) |
| A2 | 0.7x |
| B1 | 1.0x (baseline) |
| B2 | 1.3x |
| C1 | 1.6x |
| C2 | 2.0x (higher impact) |

---

## 2. Dimension Mapping

**Impact: CRITICAL**

### 2.1 Five-Axis Mapping (Backend → Display)

The backend tracks 6 skills. The UI displays 5 dimensions on a radar chart.

| Display Dimension | Backend Skills | Weight |
|------------------|----------------|--------|
| **Pronunciation** | `speaking` | 100% |
| **Vocabulary** | `vocabulary` 70% + `reading` 30% | Weighted |
| **Fluency** | `speaking` 60% + `listening` 40% | Weighted |
| **Grammar** | `grammar` 80% + `writing` 20% | Weighted |
| **Intonation** | `speaking` 50% + `listening` 50% | Weighted |

**Implementation:**

```dart
Map<String, double> mapToDisplayDimensions(Map<SkillType, SkillScore> skills) {
  final s = skills.map((k, v) => MapEntry(k, v.score));
  return {
    'Pronunciation': s[SkillType.speaking] ?? 0,
    'Vocabulary': (s[SkillType.vocabulary] ?? 0) * 0.7 + (s[SkillType.reading] ?? 0) * 0.3,
    'Fluency': (s[SkillType.speaking] ?? 0) * 0.6 + (s[SkillType.listening] ?? 0) * 0.4,
    'Grammar': (s[SkillType.grammar] ?? 0) * 0.8 + (s[SkillType.writing] ?? 0) * 0.2,
    'Intonation': (s[SkillType.speaking] ?? 0) * 0.5 + (s[SkillType.listening] ?? 0) * 0.5,
  };
}
```

---

## 3. Confidence & Thresholds

**Impact: HIGH**

### 3.1 Minimum Interaction Threshold

| Interactions | Display State |
|-------------|--------------|
| 0 | "--" for all, hourglass icon |
| 1-14 | "--" + "Scores unlock after ~15 lessons" |
| 15-24 | Scores shown with "preliminary" badge |
| 25+ | Full confidence, trend arrows |

**Confidence formula:**

```python
confidence = min(1.0, interaction_count / 25)
```

**Per-skill confidence** tracks independently — skills with confidence < 0.5 show "--" even if overall confidence is met.

---

## 4. Data Sync

**Impact: HIGH**

### 4.1 AI Service → Backend Sync

**Problem:** AI `AssessmentService` writes to MongoDB, backend `ProficiencyService` writes to PostgreSQL. No sync exists.

**Solution:** Push-based sync after each AI assessment:

```python
async def sync_assessment_to_backend(user_id, assessment):
    payload = {
        "assessed_level": assessment.level,
        "skills": { ... },
        "confidence": assessment.confidence,
        "source": "ai_assessment",
    }
    await backend_client.post("/proficiency/sync-from-ai", json=payload)
```

**Conflict resolution:** Higher confidence wins. If equal, most recent wins.

**Frequency:**
- After AI assessment completes → immediate sync
- On profile view if last sync > 1 hour → background sync
- Every 6 hours → batch reconciliation
