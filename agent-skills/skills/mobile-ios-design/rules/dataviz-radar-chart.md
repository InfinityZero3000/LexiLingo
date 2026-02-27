---
name: dataviz-radar-chart
description: Use radar/spider charts for multi-dimensional skill proficiency visualization. Display 5 axes (Pronunciation, Vocabulary, Fluency, Grammar, Intonation) with scores from 0.0 to 1.0.
impact: HIGH
---

# Radar Chart for Skill Proficiency Display

## Context

Language learning proficiency is multi-dimensional. A single score or progress bar cannot convey the learner's strengths and weaknesses across different skill areas. A radar (spider) chart with 5 axes provides immediate visual insight into the learner's profile.

## Rule

Use a custom-painted radar chart widget with 5 labeled axes to display proficiency scores. The chart should:

1. Display 5 skill dimensions: **Pronunciation**, **Vocabulary**, **Fluency**, **Grammar**, **Intonation**
2. Use normalized scores (0.0 to 1.0) for each axis
3. Show grid lines for reference (e.g., 20%, 40%, 60%, 80%, 100%)
4. Fill the data polygon with a semi-transparent accent color
5. Label each axis outside the chart with score value
6. Support dark mode with appropriate color adaptation
7. Animate score changes smoothly

## Correct Implementation

```dart
// Radar chart with CustomPainter
class ProficiencyRadarChart extends StatelessWidget {
  final Map<String, double> scores; // e.g., {'Pronunciation': 0.7, ...}
  final double size;
  final Color fillColor;
  final Color strokeColor;
  final Color gridColor;

  const ProficiencyRadarChart({
    required this.scores,
    this.size = 200,
    this.fillColor = const Color(0x336366F1),
    this.strokeColor = const Color(0xFF6366F1),
    this.gridColor = const Color(0xFFE2E8F0),
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RadarChartPainter(
        scores: scores,
        fillColor: fillColor,
        strokeColor: strokeColor,
        gridColor: gridColor,
      ),
    );
  }
}
```

## Incorrect Implementation

```dart
// Anti-pattern: Using a list of progress bars instead of radar chart
Column(
  children: scores.entries.map((e) =>
    LinearProgressIndicator(value: e.value), // Loses multi-dimensional insight
  ).toList(),
)

// Anti-pattern: Hardcoded axis count
// Always derive from data, not magic numbers
```

## Key Design Decisions

- **5 axes, not 6**: The screenshot reference shows 5 skills (Pronunciation, Vocabulary, Fluency, Grammar, Intonation). The backend has 6 skills (vocabulary, grammar, reading, listening, speaking, writing). Map backend skills → display skills: `speaking → Pronunciation + Fluency + Intonation`, `reading + listening → Vocabulary`, `grammar → Grammar`
- **Pentagon shape**: 5 axes = 72° between each axis
- **Unlock threshold**: Show "--" placeholder until user has completed ~15 lessons (enough AI interactions for confident assessment)
- **Score source**: Aggregated from AI conversation analysis (fluency_score, grammar_score from GraphCAG pipeline) + exercise results

## Accessibility

- Add `Semantics` widget wrapping the chart with a text description: "Your proficiency: Pronunciation 70%, Vocabulary 55%, Fluency 60%, Grammar 45%, Intonation 50%"
- Provide a table-based fallback for screen readers below the chart
