---
name: confidence-minimum-interactions
description: Require a minimum number of AI interactions or completed lessons before displaying proficiency scores. Prevents showing unreliable scores from too few data points.
impact: HIGH
---

# Minimum Interaction Threshold for Score Display

## Context

Proficiency scores from just 1-2 conversations are unreliable. The AI assessment service requires ~20 interactions for full confidence. Displaying unreliable scores erodes user trust.

## Rule

### Unlock Thresholds

| Condition | Threshold | Display State |
|-----------|-----------|--------------|
| No data | 0 interactions | Show "--" for all dimensions + hourglass icon |
| Insufficient | 1-14 interactions | Show "--" + "Your scores unlock after around 15 lessons" |
| Partial confidence | 15-24 interactions | Show scores with "preliminary" badge |
| Full confidence | 25+ interactions | Show scores normally with trend arrows |

### Confidence Calculation

```python
confidence = min(1.0, interaction_count / 25)
```

### Per-Skill Confidence

Each skill dimension has its own confidence based on relevant exercise count:

```python
skill_confidence = {
    "pronunciation": min(1.0, speaking_exercises / 10),
    "vocabulary": min(1.0, vocab_exercises / 10),
    "fluency": min(1.0, conversation_turns / 15),
    "grammar": min(1.0, grammar_exercises / 10),
    "intonation": min(1.0, speech_exercises / 10),
}
```

Skills with confidence < 0.5 show as "--" even if overall confidence is met.

### UI Implementation

```dart
Widget _buildScoreOrPlaceholder(String dimension, double? score, double confidence) {
  if (confidence < 0.5 || score == null) {
    return Text('--', style: TextStyle(color: Colors.grey));
  }
  return Text(
    '${(score * 100).toInt()}',
    style: TextStyle(fontWeight: FontWeight.bold),
  );
}
```
