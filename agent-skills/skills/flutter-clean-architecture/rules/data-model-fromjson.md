---
name: data-model-fromjson
description: Data layer models extend domain entities and add fromJson/toJson. Use factory constructors. Map snake_case backend fields explicitly to camelCase entity fields.
impact: HIGH
---

# Data Model Pattern (fromJson / toJson)

## Rule

Data models live in `features/<feature>/data/models/`. They:
1. Extend the domain entity (or hold an entity constructor pattern)
2. Add `factory fromJson(Map<String, dynamic> json)` and `Map<String, dynamic> toJson()`
3. Map backend snake_case keys to Dart camelCase
4. Never appear directly in widgets — pass the domain entity upward

## Correct Implementation

```dart
// features/notifications/data/models/notification_model.dart
import '../../domain/entities/notification_entity.dart';

class NotificationModel extends NotificationEntity {
  const NotificationModel({
    required super.id,
    required super.type,
    required super.title,
    required super.body,
    required super.timestamp,
    super.isRead,
    super.data,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      type: _parseType(json['type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['created_at'] as String),
      isRead: (json['is_read'] as bool?) ?? false,
      data: json['data'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'title': title,
    'body': body,
    'created_at': timestamp.toIso8601String(),
    'is_read': isRead,
    'data': data,
  };

  static NotificationType _parseType(String raw) {
    return NotificationType.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => NotificationType.system,
    );
  }
}
```

```dart
// features/level/data/models/level_model.dart
import '../../domain/entities/level_entity.dart';

class LevelModel {
  factory LevelModel.fromJson(Map<String, dynamic> json) {
    final tiers = LevelCalculator.tiers;
    final code = json['current_level'] as String;
    final tier = tiers.firstWhere((t) => t.code == code, orElse: () => tiers.first);
    return LevelEntity(
      current: tier,
      totalXP: json['total_xp'] as int,
      progressInLevel: (json['progress'] as num).toDouble(),
      xpToNextLevel: json['xp_to_next'] as int,
    ) as LevelModel;
  }
}
```

## Incorrect Implementation

```dart
// Anti-pattern: domain entity has fromJson (violates layer separation)
class LevelEntity {
  factory LevelEntity.fromJson(Map<String, dynamic> json) => ...; // ❌

  // Anti-pattern: using dynamic Map in widget directly
  final Map<String, dynamic> rawApiData; // ❌
}
```
