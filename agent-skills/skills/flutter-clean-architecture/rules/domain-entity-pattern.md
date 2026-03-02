---
name: domain-entity-pattern
description: Define all domain entities as plain Dart classes with Equatable. Entities must not contain fromJson/toJson or any Flutter/http imports.
impact: CRITICAL
---

# Domain Entity Pattern

## Context

In LexiLingo features like `notifications/`, `level/`, and `user_stats/`, business objects are often defined directly as API response models (`fromJson` data classes). This couples the UI logic to the API contract — if the backend response shape changes, the entire feature breaks.

## Rule

Domain entities live in `features/<feature>/domain/entities/`. They use `Equatable` for value equality, have no serialization code, and no platform imports.

## Correct Implementation

```dart
// features/notifications/domain/entities/notification_entity.dart
import 'package:equatable/equatable.dart';

enum NotificationType { streak, review, achievement, system }

class NotificationEntity extends Equatable {
  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? data;

  const NotificationEntity({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.data,
  });

  NotificationEntity copyWith({bool? isRead}) {
    return NotificationEntity(
      id: id, type: type, title: title, body: body,
      timestamp: timestamp,
      isRead: isRead ?? this.isRead,
      data: data,
    );
  }

  @override
  List<Object?> get props => [id, type, title, body, timestamp, isRead];
}
```

```dart
// features/level/domain/entities/level_entity.dart
import 'package:equatable/equatable.dart';

class LevelTier extends Equatable {
  final String code;    // A1, A2, B1, B2, C1, C2
  final String name;    // "Beginner", "Elementary", ...
  final int minXP;
  final int? maxXP;     // null = no cap (C2)
  final String badge;   // emoji or asset path
  final int colorValue; // hex int for Color(...)

  const LevelTier({
    required this.code,
    required this.name,
    required this.minXP,
    this.maxXP,
    required this.badge,
    required this.colorValue,
  });

  @override
  List<Object?> get props => [code, minXP, maxXP];
}

class LevelEntity extends Equatable {
  final LevelTier current;
  final int totalXP;
  final double progressInLevel; // 0.0 – 1.0
  final int xpToNextLevel;      // 0 if C2

  const LevelEntity({
    required this.current,
    required this.totalXP,
    required this.progressInLevel,
    required this.xpToNextLevel,
  });

  @override
  List<Object?> get props => [current, totalXP];
}
```

## Incorrect Implementation

```dart
// Anti-pattern: entity contains fromJson (belongs in data layer)
class NotificationEntity {
  final String id;
  NotificationEntity.fromJson(Map<String, dynamic> json)
      : id = json['id'];   // ❌ serialization in domain
}

// Anti-pattern: importing http/dio in an entity
import 'package:http/http.dart';  // ❌ platform import in domain
```

## File Location Pattern

```
features/<feature>/
  domain/
    entities/
      <feature>_entity.dart     ← this rule
    repositories/
      <feature>_repository.dart ← repository interface
    usecases/
      get_<feature>s.dart       ← use cases
  data/
    ...
  presentation/
    ...
```
