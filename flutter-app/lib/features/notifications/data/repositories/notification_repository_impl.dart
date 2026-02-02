import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';
import '../datasources/notification_local_datasource.dart';

/// Notification Repository Implementation
/// Manages notifications from local storage and FCM
class NotificationRepositoryImpl implements NotificationRepository {
  final NotificationLocalDataSource _localDataSource;

  // Stream controllers for real-time updates
  final _notificationsController =
      StreamController<List<NotificationEntity>>.broadcast();
  final _unreadCountController = StreamController<int>.broadcast();

  NotificationRepositoryImpl(this._localDataSource) {
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
    return _localDataSource.getNotifications();
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
    await _refreshStreams();
  }

  @override
  Future<void> markAllAsRead() async {
    await _localDataSource.markAllAsRead();
    await _refreshStreams();
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    await _localDataSource.deleteNotification(notificationId);
    await _refreshStreams();
  }

  @override
  Future<void> deleteAllNotifications() async {
    await _localDataSource.deleteAllNotifications();
    await _refreshStreams();
  }

  @override
  Future<List<NotificationGroup>> getGroupedNotifications() async {
    final notifications = await _localDataSource.getNotifications();

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
      groups
          .add(NotificationGroup(title: 'Yesterday', notifications: yesterday));
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
