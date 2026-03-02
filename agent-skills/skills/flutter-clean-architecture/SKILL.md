---
name: lexilingo-flutter-clean-architecture
description: Clean Architecture patterns for Flutter features in LexiLingo. Use when creating any new feature (Notifications, Level System, User Stats, Course Categories). Enforces the Domain/Data/Presentation layer split with Provider state management, repository interfaces, use cases, and Pydantic-style entities.
license: MIT
metadata:
  author: LexiLingo Team
  version: "1.0.0"
---

# Flutter Clean Architecture for LexiLingo

Every new feature in `flutter-app/lib/features/` must follow the three-layer architecture: **Domain → Data → Presentation**. This prevents coupling the UI to API response shapes, makes testing straightforward, and keeps the codebase consistent as more features are added.

## When to Apply

Use this skill when:
- Creating a new feature folder (e.g., `features/notifications/`, `features/level/`)
- Adding a new repository, use case, or Provider to an existing feature
- Fixing Provider coupling to raw API models instead of domain entities
- Reviewing or refactoring `course/`, `profile/`, or `progress/` features

## Rule Categories by Priority

| Priority | Category          | Impact   | Prefix          |
|----------|-------------------|----------|-----------------|
| 1        | Domain Layer      | CRITICAL | `domain-`       |
| 2        | Data Layer        | HIGH     | `data-`         |
| 3        | Presentation      | HIGH     | `presentation-` |
| 4        | Error Handling    | HIGH     | `error-`        |

## Quick Reference

### 1. Domain Layer (CRITICAL)

- `domain-entity-pattern` — Define plain Dart entities with `equatable`; no `fromJson`
- `domain-repository-interface` — Abstract class in domain; implementation in data
- `domain-usecase-pattern` — Single-responsibility call objects that return `Either`

### 2. Data Layer (HIGH)

- `data-model-fromjson` — Data models extend entities; add `fromJson`/`toJson`
- `data-repository-impl` — Repository calls remote + local sources; handles exceptions

### 3. Presentation Layer (HIGH)

- `presentation-provider-pattern` — `ChangeNotifier` provider; never import data/domain models in widgets
- `presentation-loading-states` — Always expose `isLoading`, `error`, `data` triad

### 4. Error Handling (HIGH)

- `error-failure-class` — Map all exceptions to typed `Failure` objects before reaching UI
