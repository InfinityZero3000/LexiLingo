import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';

void main() {
  group('NotificationEntity', () {
    test('should create NotificationEntity with required fields', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test Title',
        body: 'Test Body',
        timestamp: DateTime(2024, 1, 15, 10, 30),
      );

      expect(notification.id, '1');
      expect(notification.type, NotificationType.general);
      expect(notification.title, 'Test Title');
      expect(notification.body, 'Test Body');
      expect(notification.isRead, false);
      expect(notification.data, isNull);
    });

    test('should create NotificationEntity with all fields', () {
      final notification = NotificationEntity(
        id: '2',
        type: NotificationType.achievement,
        title: 'Achievement Unlocked',
        body: 'You earned a badge!',
        timestamp: DateTime(2024, 1, 15, 10, 30),
        isRead: true,
        data: {'badge_id': 'word_master'},
        iconIdentifier: 'emoji_events',
        colorHex: '#FFD700',
      );

      expect(notification.id, '2');
      expect(notification.type, NotificationType.achievement);
      expect(notification.isRead, true);
      expect(notification.data?['badge_id'], 'word_master');
      expect(notification.iconIdentifier, 'emoji_events');
      expect(notification.colorHex, '#FFD700');
    });

    test('markAsRead should return copy with isRead true', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now(),
        isRead: false,
      );

      final readNotification = notification.markAsRead();

      expect(notification.isRead, false); // Original unchanged
      expect(readNotification.isRead, true);
      expect(readNotification.id, notification.id);
      expect(readNotification.title, notification.title);
    });

    test('copyWith should create copy with updated fields', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Original Title',
        body: 'Original Body',
        timestamp: DateTime(2024, 1, 15),
      );

      final updatedNotification = notification.copyWith(
        title: 'Updated Title',
        isRead: true,
      );

      expect(updatedNotification.id, '1');
      expect(updatedNotification.title, 'Updated Title');
      expect(updatedNotification.body, 'Original Body');
      expect(updatedNotification.isRead, true);
    });
  });

  group('NotificationEntity - isToday', () {
    test('should return true for notification from today', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now(),
      );

      expect(notification.isToday, true);
    });

    test('should return false for notification from yesterday', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(notification.isToday, false);
    });
  });

  group('NotificationEntity - isYesterday', () {
    test('should return true for notification from yesterday', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(notification.isYesterday, true);
    });

    test('should return false for notification from today', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now(),
      );

      expect(notification.isYesterday, false);
    });

    test('should return false for notification from 2 days ago', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now().subtract(const Duration(days: 2)),
      );

      expect(notification.isYesterday, false);
    });
  });

  group('NotificationEntity - relativeTimeString', () {
    test('should return "Just now" for < 1 minute ago', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now().subtract(const Duration(seconds: 30)),
      );

      expect(notification.relativeTimeString, 'Just now');
    });

    test('should return minutes format for < 1 hour', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      );

      expect(notification.relativeTimeString, '15m ago');
    });

    test('should return hours format for < 24 hours', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now().subtract(const Duration(hours: 5)),
      );

      expect(notification.relativeTimeString, '5h ago');
    });

    test('should return "Yesterday" for yesterday', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: yesterday,
      );

      expect(notification.relativeTimeString, 'Yesterday');
    });

    test('should return days format for < 7 days', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
      );

      expect(notification.relativeTimeString, '3d ago');
    });
  });

  group('NotificationEntity - fromFcm factory', () {
    test('should create notification from FCM data', () {
      final notification = NotificationEntity.fromFcm(
        id: 'fcm_123',
        title: 'FCM Title',
        body: 'FCM Body',
        data: {'type': 'achievement', 'target_id': 'badge_1'},
      );

      expect(notification.id, 'fcm_123');
      expect(notification.title, 'FCM Title');
      expect(notification.body, 'FCM Body');
      expect(notification.type, NotificationType.achievement);
      expect(notification.isRead, false);
      expect(notification.data?['target_id'], 'badge_1');
    });

    test('should parse streak_reminder type', () {
      final notification = NotificationEntity.fromFcm(
        id: '1',
        title: 'Streak',
        body: 'Body',
        data: {'type': 'streak_reminder'},
      );

      expect(notification.type, NotificationType.streakReminder);
      expect(notification.iconIdentifier, 'local_fire_department');
      expect(notification.colorHex, '#FF9800');
    });

    test('should parse lesson_reminder type', () {
      final notification = NotificationEntity.fromFcm(
        id: '1',
        title: 'Lesson',
        body: 'Body',
        data: {'type': 'lesson_reminder'},
      );

      expect(notification.type, NotificationType.lessonReminder);
      expect(notification.iconIdentifier, 'schedule');
    });

    test('should default to general type for unknown', () {
      final notification = NotificationEntity.fromFcm(
        id: '1',
        title: 'Unknown',
        body: 'Body',
        data: {'type': 'unknown_type'},
      );

      expect(notification.type, NotificationType.general);
    });

    test('should default to general type when no type in data', () {
      final notification = NotificationEntity.fromFcm(
        id: '1',
        title: 'No Type',
        body: 'Body',
      );

      expect(notification.type, NotificationType.general);
    });
  });

  group('NotificationEntity - getters from data', () {
    test('targetId should return target_id from data', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now(),
        data: {'target_id': 'course_123'},
      );

      expect(notification.targetId, 'course_123');
    });

    test('targetId should return null when not in data', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now(),
      );

      expect(notification.targetId, isNull);
    });

    test('route should return route from data', () {
      final notification = NotificationEntity(
        id: '1',
        type: NotificationType.general,
        title: 'Test',
        body: 'Body',
        timestamp: DateTime.now(),
        data: {'route': '/courses/123'},
      );

      expect(notification.route, '/courses/123');
    });
  });

  group('NotificationGroup', () {
    test('should create NotificationGroup with notifications', () {
      final notifications = [
        NotificationEntity(
          id: '1',
          type: NotificationType.general,
          title: 'Test 1',
          body: 'Body 1',
          timestamp: DateTime.now(),
          isRead: false,
        ),
        NotificationEntity(
          id: '2',
          type: NotificationType.general,
          title: 'Test 2',
          body: 'Body 2',
          timestamp: DateTime.now(),
          isRead: true,
        ),
      ];

      final group = NotificationGroup(
        title: 'Today',
        notifications: notifications,
      );

      expect(group.title, 'Today');
      expect(group.notifications.length, 2);
      expect(group.hasUnread, true);
      expect(group.unreadCount, 1);
    });

    test('hasUnread should return false when all read', () {
      final notifications = [
        NotificationEntity(
          id: '1',
          type: NotificationType.general,
          title: 'Test 1',
          body: 'Body 1',
          timestamp: DateTime.now(),
          isRead: true,
        ),
        NotificationEntity(
          id: '2',
          type: NotificationType.general,
          title: 'Test 2',
          body: 'Body 2',
          timestamp: DateTime.now(),
          isRead: true,
        ),
      ];

      final group = NotificationGroup(
        title: 'Today',
        notifications: notifications,
      );

      expect(group.hasUnread, false);
      expect(group.unreadCount, 0);
    });
  });

  group('NotificationType', () {
    test('should have all expected values', () {
      expect(NotificationType.values, contains(NotificationType.streakReminder));
      expect(NotificationType.values, contains(NotificationType.lessonReminder));
      expect(NotificationType.values, contains(NotificationType.achievement));
      expect(NotificationType.values, contains(NotificationType.newContent));
      expect(NotificationType.values, contains(NotificationType.weeklySummary));
      expect(NotificationType.values, contains(NotificationType.social));
      expect(NotificationType.values, contains(NotificationType.system));
      expect(NotificationType.values, contains(NotificationType.general));
    });
  });
}
