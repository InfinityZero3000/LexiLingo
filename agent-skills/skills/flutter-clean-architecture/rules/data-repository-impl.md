---
name: data-repository-impl
description: Repository implementations in the data layer combine remote and local data sources, map exceptions to Failures, and return Either<Failure, T>.
impact: HIGH
---

# Data Repository Implementation Pattern

## Rule

Concrete repository classes live in `features/<feature>/data/repositories/`. They:
1. Implement the domain `Repository` abstract class
2. Call `RemoteDataSource` first, fall back to `LocalDataSource` if needed
3. Wrap all calls in `try/catch`, converting exceptions to `Failure` objects
4. Return `Right(entity)` on success, `Left(failure)` on error

## Correct Implementation

```dart
// features/notifications/data/repositories/notification_repository_impl.dart
import 'package:dartz/dartz.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/error/exceptions.dart';
import '../datasources/notification_remote_datasource.dart';
import '../datasources/notification_local_datasource.dart';
import 'dart:async';

class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationRemoteDataSource remoteDataSource;
  final NotificationLocalDataSource localDataSource;

  const NotificationRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Either<Failure, List<NotificationEntity>>> getNotifications() async {
    try {
      final remote = await remoteDataSource.fetchNotifications();
      await localDataSource.cacheNotifications(remote);
      return Right(remote);
    } on ServerException catch (e) {
      // Fallback: return cached data with stale warning
      try {
        final cached = await localDataSource.getCachedNotifications();
        return Right(cached);
      } catch (_) {
        return Left(ServerFailure(message: e.message));
      }
    } on NetworkException {
      try {
        final cached = await localDataSource.getCachedNotifications();
        return Right(cached);
      } catch (_) {
        return const Left(NetworkFailure());
      }
    }
  }

  @override
  Future<Either<Failure, NotificationEntity>> markAsRead(String id) async {
    try {
      await remoteDataSource.markAsRead(id);
      await localDataSource.markAsRead(id);
      final updated = await localDataSource.getNotificationById(id);
      return Right(updated);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> markAllAsRead() async {
    try {
      await remoteDataSource.markAllAsRead();
      await localDataSource.markAllAsRead();
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Future<Either<Failure, void>> deleteNotification(String id) async {
    try {
      await remoteDataSource.deleteNotification(id);
      await localDataSource.deleteNotification(id);
      return const Right(null);
    } on ServerException catch (e) {
      return Left(ServerFailure(message: e.message));
    }
  }

  @override
  Stream<NotificationEntity> get incomingNotifications =>
      remoteDataSource.incomingNotifications;
}
```

## Remote Data Source Pattern

```dart
// features/notifications/data/datasources/notification_remote_datasource.dart
import '../../../../core/network/api_client.dart';
import '../../../../core/error/exceptions.dart';
import '../models/notification_model.dart';
import '../../domain/entities/notification_entity.dart';

abstract class NotificationRemoteDataSource {
  Future<List<NotificationEntity>> fetchNotifications();
  Future<void> markAsRead(String id);
  Future<void> markAllAsRead();
  Future<void> deleteNotification(String id);
  Stream<NotificationEntity> get incomingNotifications;
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final ApiClient apiClient;
  const NotificationRemoteDataSourceImpl(this.apiClient);

  @override
  Future<List<NotificationEntity>> fetchNotifications() async {
    final response = await apiClient.get('/api/notifications');
    if (response.statusCode != 200) {
      throw ServerException(message: 'Failed to fetch notifications');
    }
    final List data = response.data['data'] as List;
    return data.map((e) => NotificationModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ... other methods
}
```

## Incorrect Implementation

```dart
// Anti-pattern: repository returns raw Map
class NotificationRepositoryImpl {
  Future<List<Map<String, dynamic>>> getNotifications() async { ... } // ❌

  // Anti-pattern: no error handling — exceptions bubble to UI
  Future<List<NotificationEntity>> getNotifications() async {
    return await remoteDataSource.fetchNotifications(); // ❌ no try/catch
  }
}
```
