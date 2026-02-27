# LexiLingo Team - Mobile iOS Design for Flutter

**Version 1.0.0**  
LexiLingo Team (adapted from wshobson/agents)  
February 2026

> **Note:**  
> This document is for agents and LLMs to follow when building or maintaining  
> mobile UI components. Optimized for AI-assisted workflows.

---

## Abstract

Mobile UI design patterns adapted from Apple's Human Interface Guidelines for cross-platform Flutter development. Covers layout systems, navigation patterns, visual hierarchy, accessibility, and data visualization for building polished mobile interfaces.

---

## Table of Contents

1. [Data Visualization](#1-data-visualization)
2. [Card Design](#2-card-design)

---

## 1. Data Visualization

**Impact: HIGH**

### 1.1 Radar Chart for Skill Proficiency Display

Use a custom-painted radar/spider chart with 5 labeled axes to display language proficiency scores.

**5 Display Dimensions:**
- Pronunciation
- Vocabulary
- Fluency
- Grammar
- Intonation

**Design Requirements:**
- Pentagon shape (72° between axes)
- Grid lines at 20%, 40%, 60%, 80%, 100%
- Semi-transparent fill for data polygon
- Axis labels with score values outside the chart
- Support dark/light mode
- Animate score transitions
- Show "--" placeholder until confidence threshold met

**Correct: Custom painter radar chart**

```dart
class ProficiencyRadarChart extends StatelessWidget {
  final Map<String, double> scores;
  final double size;
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _RadarChartPainter(scores: scores),
    );
  }
}
```

**Incorrect: Linear progress bars for multi-dimensional data**

```dart
// Loses the comparative insight between dimensions
Column(children: scores.map((s) => LinearProgressIndicator(value: s)).toList())
```

---

## 2. Card Design

**Impact: HIGH**

### 2.1 Flat Pastel Cards (Replaces Glassmorphism)

Use flat pastel background with subtle colored border. No BackdropFilter, no blur, no heavy shadows.

**Correct:**

```dart
Container(
  decoration: BoxDecoration(
    color: bgColor,                                  // Flat pastel
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
  ),
)
```

**Incorrect:**

```dart
ClipRRect(
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),  // GPU heavy
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [...]),         // Unnecessary
        boxShadow: [BoxShadow(blurRadius: 20)],         // Too heavy
      ),
    ),
  ),
)
```
