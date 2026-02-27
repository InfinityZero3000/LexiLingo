---
name: card-flat-pastel
description: Use flat pastel background cards with subtle borders instead of glassmorphism. Provides better readability, consistent cross-platform rendering, and lower GPU overhead.
impact: HIGH
---

# Flat Pastel Card Design Pattern

## Context

The LexiLingo app had inconsistent card styles: glassmorphism (BackdropFilter + blur), solid gradients with box shadows, and flat pastel cards. Glassmorphism causes performance issues on low-end devices and renders inconsistently across platforms.

## Rule

Use flat pastel background cards with a subtle colored border. No `BackdropFilter`, no `ImageFilter.blur`, no `LinearGradient`, no heavy `boxShadow`.

## Correct Implementation

```dart
Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: bgColor,                                    // Single flat pastel color
    borderRadius: BorderRadius.circular(12),           // Consistent radius
    border: Border.all(
      color: accentColor.withValues(alpha: 0.2),       // Subtle border
    ),
  ),
  child: content,
)
```

### Example Color Palette

| Category     | Background         | Accent/Border      |
|-------------|-------------------|-------------------|
| AI Tutor    | `Color(0xFFE0E7FF)` | `Color(0xFF3B82F6)` |
| Vocabulary  | `Color(0xFFFFF3E0)` | `Color(0xFFF59E0B)` |
| Grammar     | `Color(0xFFEDE9FE)` | `Color(0xFF8B5CF6)` |
| Streak      | `Color(0xFFFEF3C7)` | `Color(0xFFF97316)` |
| Progress    | `Color(0xFFDBEAFE)` | `Color(0xFF3B82F6)` |

## Incorrect Implementation

```dart
// Anti-pattern: Glassmorphism
ClipRRect(
  borderRadius: BorderRadius.circular(20),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),  // Heavy GPU cost
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(                        // Unnecessary gradient
          colors: [
            Colors.white.withValues(alpha: 0.1),
            Colors.white.withValues(alpha: 0.05),
          ],
        ),
      ),
    ),
  ),
)

// Anti-pattern: Heavy box shadows
BoxDecoration(
  boxShadow: [
    BoxShadow(blurRadius: 20, offset: Offset(0, 10)),  // Too heavy
    BoxShadow(blurRadius: 10, offset: Offset(0, 4)),   // Double shadow
  ],
)
```

## When to Break This Rule

- App bar backgrounds where blur is standard platform behavior
- Modal bottom sheets (platform convention)
- Never for regular content cards, stat cards, or action buttons
