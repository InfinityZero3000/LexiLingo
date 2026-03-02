---
name: domain-repository-interface
description: Define repository contracts as abstract classes in the domain layer. Never import http, dio, or hive in the interface — those belong in the data layer implementation.
impact: CRITICAL
---

# Domain Repository Interface Pattern

## Rule

Each feature has one abstract `Repository` class in `domain/repositories/`. Methods return `Future<Either<Failure, T>>`. The data layer provides the concrete implementation.

## Correct Implementation

```dart
// features/notifications/domain/repositories/notification_repository.dart
import '../entities/notification_entity.dart';
import '../../../../core/error/failures.dart';
import 'package:dartz/dartz.dart';

abstract class NotificationRepository {
  /// Returns all notifications for the current user, newest first.
  Future<Either<Failure, List<NotificationEntity>>> getNotifications();

  /// Marks a single notification as read. Returns updated entity.
  Future<Either<Failure, NotificationEntity>> markAsRead(String notificationId);

  /// Marks every notification as read.
  Future<Either<Failure, void>> markAllAsRead();

  /// Deletes a notification by id.
  Future<Either<Failure, void>> deleteNotification(String notificationId);

  /// Stream of new incoming notifications (Firebase FCM).
  Stream<NotificationEntity> get incomingNotifications;
}
```

```dart
// features/level/domain/repositories/level_repository.dart
import '../entities/level_entity.dart';
import '../../../../core/error/failures.dart';
import 'package:dartz/dartz.dart';

abstract class LevelRepository {
  Future<Either<Failure, LevelEntity>> getCurrentLevel();
  Future<Either<Failure, void>> refreshLevel();
}
```

## Correct Use Case Pattern

```dart
// features/notifications/domain/usecases/get_notifications.dart
import '../repositories/notification_repository.dart';
import '../entities/notification_entity.dart';
import '../../../../core/error/failures.dart';
import 'package:dartz/dartz.dart';

class GetNotifications {
  final NotificationRepository repository;
  const GetNotifications(this.repository);

  Future<Either<Failure, List<NotificationEntity>>> call() {
    return repository.getNotifications();
  }
}
```

## Incorrect Implementation

```dart
// Anti-pattern: concrete HTTP in domain
abstract class NotificationRepository {
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final res = await http.get(Uri.parse('/api/notifications')); // ❌
    return jsonDecode(res.body);
  }
}

// Anti-pattern: returns raw JSON map
Future<Map<String, dynamic>> getCurrentLevel();  // ❌ should be LevelEntity
```
