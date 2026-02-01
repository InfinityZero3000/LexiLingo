import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:lexilingo_app/features/notifications/data/datasources/notification_local_datasource.dart';

/// Mock implementation of NotificationLocalDataSource for testing
class MockNotificationLocalDataSource implements NotificationLocalDataSource {
  List<NotificationEntity> _notifications = [];

  @override
  Future<List<NotificationEntity>> getNotifications() async {
    return List.from(_notifications)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  @override
  Future<void> saveNotifications(List<NotificationEntity> notifications) async {
    _notifications = List.from(notifications);
  }

  @override
  Future<void> addNotification(NotificationEntity notification) async {
    _notifications.insert(0, notification);
  }

  @override
  Future<void> markAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notifications[index] = _notifications[index].markAsRead();
    }
  }

  @override
  Future<void> markAllAsRead() async {
    _notifications = _notifications.map((n) => n.markAsRead()).toList();
  }

  @override
  Future<void> deleteNotification(String id) async {
    _notifications.removeWhere((n) => n.id == id);
  }

  @override
  Future<void> deleteAllNotifications() async {
    _notifications.clear();
  }

  @override
  Future<int> getUnreadCount() async {
    return _notifications.where((n) => !n.isRead).length;
  }

  @override
  Future<NotificationEntity?> getNotificationById(String id) async {
    try {
      return _notifications.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }
}

void main() {
  late MockNotificationLocalDataSource mockDataSource;
  late NotificationRepositoryImpl repository;

  setUp(() {
    mockDataSource = MockNotificationLocalDataSource();
    repository = NotificationRepositoryImpl(mockDataSource);
  });

  NotificationEntity createNotification({
    String id = '1',
    String title = 'Test',
    bool isRead = false,
    DateTime? timestamp,
  }) {
    return NotificationEntity(
      id: id,
      type: NotificationType.general,
      title: title,
      body: 'Test Body',
      timestamp: timestamp ?? DateTime.now(),
      isRead: isRead,
    );
  }

  group('NotificationRepositoryImpl', () {
    test('getNotifications should return empty list initially', () async {
      final notifications = await repository.getNotifications();
      expect(notifications, isEmpty);
    });

    test('addNotification should add notification', () async {
      final notification = createNotification();
      await repository.addNotification(notification);

      final notifications = await repository.getNotifications();
      expect(notifications.length, 1);
      expect(notifications.first.id, '1');
    });

    test('getUnreadCount should return count of unread notifications', () async {
      await repository.addNotification(createNotification(id: '1', isRead: false));
      await repository.addNotification(createNotification(id: '2', isRead: true));
      await repository.addNotification(createNotification(id: '3', isRead: false));

      final unreadCount = await repository.getUnreadCount();
      expect(unreadCount, 2);
    });

    test('markAsRead should mark notification as read', () async {
      await repository.addNotification(createNotification(id: '1', isRead: false));

      await repository.markAsRead('1');

      final notifications = await repository.getNotifications();
      expect(notifications.first.isRead, true);
    });

    test('markAllAsRead should mark all notifications as read', () async {
      await repository.addNotification(createNotification(id: '1', isRead: false));
      await repository.addNotification(createNotification(id: '2', isRead: false));
      await repository.addNotification(createNotification(id: '3', isRead: false));

      await repository.markAllAsRead();

      final unreadCount = await repository.getUnreadCount();
      expect(unreadCount, 0);
    });

    test('deleteNotification should remove notification', () async {
      await repository.addNotification(createNotification(id: '1'));
      await repository.addNotification(createNotification(id: '2'));

      await repository.deleteNotification('1');

      final notifications = await repository.getNotifications();
      expect(notifications.length, 1);
      expect(notifications.first.id, '2');
    });

    test('deleteAllNotifications should clear all notifications', () async {
      await repository.addNotification(createNotification(id: '1'));
      await repository.addNotification(createNotification(id: '2'));

      await repository.deleteAllNotifications();

      final notifications = await repository.getNotifications();
      expect(notifications, isEmpty);
    });

    test('getNotificationById should return notification', () async {
      await repository.addNotification(createNotification(id: '1', title: 'First'));
      await repository.addNotification(createNotification(id: '2', title: 'Second'));

      final notification = await repository.getNotificationById('2');

      expect(notification, isNotNull);
      expect(notification!.title, 'Second');
    });

    test('getNotificationById should return null for non-existent id', () async {
      await repository.addNotification(createNotification(id: '1'));

      final notification = await repository.getNotificationById('non_existent');

      expect(notification, isNull);
    });
  });

  group('NotificationRepositoryImpl - getGroupedNotifications', () {
    test('should group notifications by Today, Yesterday, Earlier', () async {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      final earlier = now.subtract(const Duration(days: 5));

      await repository.addNotification(createNotification(
        id: '1',
        title: 'Today Notification',
        timestamp: now,
      ));
      await repository.addNotification(createNotification(
        id: '2',
        title: 'Yesterday Notification',
        timestamp: yesterday,
      ));
      await repository.addNotification(createNotification(
        id: '3',
        title: 'Earlier Notification',
        timestamp: earlier,
      ));

      final groups = await repository.getGroupedNotifications();

      expect(groups.length, 3);
      expect(groups[0].title, 'Today');
      expect(groups[0].notifications.length, 1);
      expect(groups[1].title, 'Yesterday');
      expect(groups[1].notifications.length, 1);
      expect(groups[2].title, 'Earlier');
      expect(groups[2].notifications.length, 1);
    });

    test('should return empty list when no notifications', () async {
      final groups = await repository.getGroupedNotifications();
      expect(groups, isEmpty);
    });

    test('should skip empty groups', () async {
      final now = DateTime.now();
      await repository.addNotification(createNotification(
        id: '1',
        timestamp: now,
      ));

      final groups = await repository.getGroupedNotifications();

      expect(groups.length, 1);
      expect(groups[0].title, 'Today');
    });
  });

  group('NotificationRepositoryImpl - streams', () {
    test('notificationsStream should emit updates', () async {
      // Listen to stream
      final streamNotifications = <List<NotificationEntity>>[];
      repository.notificationsStream.listen((notifications) {
        streamNotifications.add(notifications);
      });

      // Add notification
      await repository.addNotification(createNotification(id: '1'));

      // Give stream time to emit
      await Future.delayed(const Duration(milliseconds: 50));

      expect(streamNotifications.isNotEmpty, true);
    });

    test('unreadCountStream should emit updates', () async {
      // Listen to stream
      final streamCounts = <int>[];
      repository.unreadCountStream.listen((count) {
        streamCounts.add(count);
      });

      // Add notifications
      await repository.addNotification(createNotification(id: '1', isRead: false));
      await repository.addNotification(createNotification(id: '2', isRead: false));

      // Give stream time to emit
      await Future.delayed(const Duration(milliseconds: 50));

      expect(streamCounts.isNotEmpty, true);
    });
  });
}
