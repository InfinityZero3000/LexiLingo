---
name: dimension-five-axis
description: Map the 6 backend skill types to 5 display dimensions for the proficiency radar chart. This mapping bridges the backend data model (vocabulary, grammar, reading, listening, speaking, writing) with the user-facing display (Pronunciation, Vocabulary, Fluency, Grammar, Intonation).
impact: CRITICAL
---

# Five-Axis Proficiency Dimension Mapping

## Context

The backend `user_skill_scores` table tracks 6 skills: vocabulary, grammar, reading, listening, speaking, writing. The proficiency UI displays 5 dimensions on a radar chart: Pronunciation, Vocabulary, Fluency, Grammar, Intonation. This rule defines the mapping.

## Rule

### Mapping Table

| Display Dimension | Backend Skills Used | Weight | Score Formula |
|------------------|-------------------|--------|---------------|
| **Pronunciation** | `speaking` | 100% | `speaking.score` |
| **Vocabulary** | `vocabulary`, `reading` | 70/30 | `vocab.score * 0.7 + reading.score * 0.3` |
| **Fluency** | `speaking`, `listening` | 60/40 | `speaking.score * 0.6 + listening.score * 0.4` |
| **Grammar** | `grammar`, `writing` | 80/20 | `grammar.score * 0.8 + writing.score * 0.2` |
| **Intonation** | `speaking`, `listening` | 50/50 | `speaking.score * 0.5 + listening.score * 0.5` |

### Rationale

- **Pronunciation**: Directly maps to speaking skill since pronunciation is a speaking subskill
- **Vocabulary**: Primarily vocabulary knowledge, supported by reading comprehension which demonstrates word understanding in context
- **Fluency**: How smoothly the user communicates (speaking) and comprehends (listening)
- **Grammar**: Primarily grammar, with writing as evidence of grammar application
- **Intonation**: Speech melody requires both production (speaking) and perception (listening)

### Implementation

```dart
/// Map 6 backend skills to 5 display dimensions
class ProficiencyDimensionMapper {
  static Map<String, double> mapToDisplayDimensions(
    Map<SkillType, SkillScore> skills,
  ) {
    final speaking = skills[SkillType.speaking]?.score ?? 0;
    final listening = skills[SkillType.listening]?.score ?? 0;
    final vocabulary = skills[SkillType.vocabulary]?.score ?? 0;
    final grammar = skills[SkillType.grammar]?.score ?? 0;
    final reading = skills[SkillType.reading]?.score ?? 0;
    final writing = skills[SkillType.writing]?.score ?? 0;
    
    return {
      'Pronunciation': speaking,
      'Vocabulary': vocabulary * 0.7 + reading * 0.3,
      'Fluency': speaking * 0.6 + listening * 0.4,
      'Grammar': grammar * 0.8 + writing * 0.2,
      'Intonation': speaking * 0.5 + listening * 0.5,
    };
  }
}
```

### When Users Have No Data

Display "--" for all dimensions until:
- User has completed at least 15 lessons OR
- User has had at least 10 AI conversations OR
- User has taken the placement test

Show a message: "Your scores will show after you do first few lessons. Start learning now!"

### Backend API Response Format

```json
{
  "display_dimensions": {
    "pronunciation": 0.65,
    "vocabulary": 0.72,
    "fluency": 0.58,
    "grammar": 0.45,
    "intonation": 0.52
  },
  "confidence": 0.85,
  "unlock_threshold_met": true,
  "interactions_count": 23,
  "last_updated": "2026-02-27T10:30:00Z"
}
```
