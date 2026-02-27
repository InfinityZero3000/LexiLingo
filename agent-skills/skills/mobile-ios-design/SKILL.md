---
name: lexilingo-mobile-ios-design
description: Mobile UI design patterns inspired by Apple HIG, adapted for Flutter cross-platform development. Use when designing profile screens, data visualization (radar charts, progress rings), card-based layouts, or ensuring consistent visual hierarchy across the app.
license: MIT
metadata:
  author: LexiLingo Team (adapted from wshobson/agents)
  version: "1.0.0"
---

# Mobile iOS Design for Flutter

Best practices for building polished, native-feeling mobile interfaces in Flutter, inspired by Apple's Human Interface Guidelines (HIG) principles: Clarity, Deference, Depth.

## When to Apply

Use this skill when:
- Designing profile screens, dashboards, or data visualization UIs
- Building radar/spider charts for multi-dimensional data display
- Creating card-based layouts with consistent styling
- Implementing navigation patterns (tabs, stacks, sheets)
- Ensuring accessibility (Dynamic Type, VoiceOver equivalents)
- Designing for light/dark mode with semantic colors
- Building adaptive layouts for phone and tablet

## Rule Categories by Priority

| Priority | Category             | Impact   | Prefix          |
| -------- | -------------------- | -------- | --------------- |
| 1        | Visual Hierarchy     | CRITICAL | `visual-`       |
| 2        | Layout Patterns      | HIGH     | `layout-`       |
| 3        | Data Visualization   | HIGH     | `dataviz-`      |
| 4        | Card Design          | HIGH     | `card-`         |
| 5        | Accessibility        | MEDIUM   | `a11y-`         |
| 6        | Animation            | MEDIUM   | `animation-`    |

## Quick Reference

### 1. Visual Hierarchy (CRITICAL)

- `visual-semantic-colors` - Use semantic colors for automatic dark mode
- `visual-typography-scale` - Follow platform typography scale
- `visual-spacing-system` - Use consistent 4pt/8pt spacing grid

### 2. Layout Patterns (HIGH)

- `layout-safe-areas` - Respect safe area insets
- `layout-adaptive-grid` - Use responsive grid for different screen sizes
- `layout-scroll-behavior` - Proper scroll view nesting and physics

### 3. Data Visualization (HIGH)

- `dataviz-radar-chart` - Multi-axis radar for skill proficiency display
- `dataviz-progress-rings` - Circular progress indicators
- `dataviz-stat-cards` - Compact stat display cards

### 4. Card Design (HIGH)

- `card-flat-pastel` - Flat pastel background with subtle border
- `card-consistent-radius` - Consistent border radius across cards
- `card-information-density` - Appropriate info density per card

### 5. Accessibility (MEDIUM)

- `a11y-semantic-labels` - Add Semantics widgets for screen readers
- `a11y-touch-targets` - Minimum 44x44pt touch targets
- `a11y-color-contrast` - WCAG AA contrast ratios

### 6. Animation (MEDIUM)

- `animation-meaningful` - Use animation to convey state changes
- `animation-performance` - Avoid expensive animations on scroll
- `animation-duration` - Follow platform timing conventions
