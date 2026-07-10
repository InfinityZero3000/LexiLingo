import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/notification_local_datasource.dart';
import '../datasources/notification_remote_datasource.dart';

/// Notification Repository Implementation
/// Manages notifications from local storage and FCM
class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationLocalDataSource _localDataSource;
  final NotificationRemoteDataSource? _remoteDataSource;

  // Stream controllers for real-time updates
  final _notificationsController =
      StreamController<List<NotificationEntity>>.broadcast();
  final _unreadCountController = StreamController<int>.broadcast();

  NotificationRepositoryImpl(
    this._localDataSource, {
    NotificationRemoteDataSource? remoteDataSource,
  }) : _remoteDataSource = remoteDataSource {
    // Initialize streams with current data
    _refreshStreams();
  }

  Future<void> _refreshStreams() async {
    try {
      final notifications = await _localDataSource.getNotifications();
      _notificationsController.add(notifications);

      final unreadCount = await _localDataSource.getUnreadCount();
      _unreadCountController.add(unreadCount);
    } catch (e) {
      debugPrint('Error refreshing notification streams: $e');
    }
  }

  @override
  Future<List<NotificationEntity>> getNotifications() async {
    final local = await _localDataSource.getNotifications();
    if (_remoteDataSource == null) return local;

    try {
      final remote = await _remoteDataSource.getNotifications();
      final merged = <String, NotificationEntity>{
        for (final item in local) item.id: item,
        for (final item in remote) item.id: item,
      }.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      await _localDataSource.saveNotifications(merged);
      return merged;
    } catch (e) {
      debugPrint('Remote notification sync failed: $e');
      return local;
    }
  }

  @override
  Future<int> getUnreadCount() async {
    return _localDataSource.getUnreadCount();
  }

  @override
  Future<NotificationEntity?> getNotificationById(String id) async {
    return _localDataSource.getNotificationById(id);
  }

  @override
  Future<void> addNotification(NotificationEntity notification) async {
    await _localDataSource.addNotification(notification);
    await _refreshStreams();
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _localDataSource.markAsRead(notificationId);
    try {
      await _remoteDataSource?.markAsRead(notificationId);
    } catch (e) {
      debugPrint('Remote mark notification read failed: $e');
    }
    await _refreshStreams();
  }

  @override
  Future<void> markAllAsRead() async {
    await _localDataSource.markAllAsRead();
    try {
      await _remoteDataSource?.markAllAsRead();
    } catch (e) {
      debugPrint('Remote mark all notifications read failed: $e');
    }
    await _refreshStreams();
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    await _localDataSource.deleteNotification(notificationId);
    try {
      await _remoteDataSource?.deleteNotification(notificationId);
    } catch (e) {
      debugPrint('Remote delete notification failed: $e');
    }
    await _refreshStreams();
  }

  @override
  Future<void> deleteAllNotifications() async {
    await _localDataSource.deleteAllNotifications();
    try {
      await _remoteDataSource?.deleteAllNotifications();
    } catch (e) {
      debugPrint('Remote delete all notifications failed: $e');
    }
    await _refreshStreams();
  }

  @override
  Future<List<NotificationGroup>> getGroupedNotifications() async {
    final notifications = await getNotifications();

    final today = <NotificationEntity>[];
    final yesterday = <NotificationEntity>[];
    final earlier = <NotificationEntity>[];

    for (final notification in notifications) {
      if (notification.isToday) {
        today.add(notification);
      } else if (notification.isYesterday) {
        yesterday.add(notification);
      } else {
        earlier.add(notification);
      }
    }

    final groups = <NotificationGroup>[];

    if (today.isNotEmpty) {
      groups.add(NotificationGroup(title: 'Today', notifications: today));
    }

    if (yesterday.isNotEmpty) {
      groups.add(
        NotificationGroup(title: 'Yesterday', notifications: yesterday),
      );
    }

    if (earlier.isNotEmpty) {
      groups.add(NotificationGroup(title: 'Earlier', notifications: earlier));
    }

    return groups;
  }

  @override
  Stream<List<NotificationEntity>> get notificationsStream =>
      _notificationsController.stream;

  @override
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  /// Dispose stream controllers
  void dispose() {
    _notificationsController.close();
    _unreadCountController.close();
  }
}
