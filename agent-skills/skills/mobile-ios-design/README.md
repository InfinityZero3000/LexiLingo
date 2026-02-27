# Mobile iOS Design for Flutter

Adapted from [wshobson/agents mobile-ios-design](https://github.com/wshobson/agents) for LexiLingo Flutter development.

## Overview

Design patterns for building polished mobile interfaces in Flutter, guided by Apple HIG principles (Clarity, Deference, Depth) but adapted for cross-platform use.

## Key Decisions for LexiLingo

1. **Flat pastel cards** over glassmorphism — better performance, consistent rendering
2. **Radar chart** for proficiency display — multi-dimensional skill visualization
3. **8pt spacing grid** — consistent spacing across all screens
4. **Semantic colors** — automatic dark mode support via `Theme.of(context)`

## Files

- `SKILL.md` — Full skill description and rule index
- `rules/` — Individual rule files
  - `_sections.md` — Section definitions
  - `dataviz-radar-chart.md` — Radar chart for proficiency display
  - `card-flat-pastel.md` — Flat pastel card pattern (replaces glassmorphism)
