import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:lexilingo_app/features/notifications/domain/services/review_reminder_notification_sync_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

class MemoryNotificationRepository implements NotificationRepository {
  final List<NotificationEntity> notifications = [];
  final _notificationsController =
      StreamController<List<NotificationEntity>>.broadcast();
  final _unreadCountController = StreamController<int>.broadcast();

  @override
  Future<void> addNotification(NotificationEntity notification) async {
    notifications.removeWhere((n) => n.id == notification.id);
    notifications.insert(0, notification);
    _emit();
  }

  @override
  Future<void> deleteAllNotifications() async {
    notifications.clear();
    _emit();
  }

  @override
  Future<void> deleteNotification(String notificationId) async {
    notifications.removeWhere((n) => n.id == notificationId);
    _emit();
  }

  @override
  Future<List<NotificationGroup>> getGroupedNotifications() async {
    return [NotificationGroup(title: 'Today', notifications: notifications)];
  }

  @override
  Future<NotificationEntity?> getNotificationById(String id) async {
    final matches = notifications.where((n) => n.id == id);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Future<List<NotificationEntity>> getNotifications() async {
    return List.of(notifications);
  }

  @override
  Future<int> getUnreadCount() async {
    return notifications.where((n) => !n.isRead).length;
  }

  @override
  Future<void> markAllAsRead() async {
    for (var i = 0; i < notifications.length; i++) {
      notifications[i] = notifications[i].markAsRead();
    }
    _emit();
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    final index = notifications.indexWhere((n) => n.id == notificationId);
    if (index == -1) return;
    notifications[index] = notifications[index].markAsRead();
    _emit();
  }

  @override
  Stream<List<NotificationEntity>> get notificationsStream =>
      _notificationsController.stream;

  @override
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  void dispose() {
    _notificationsController.close();
    _unreadCountController.close();
  }

  void _emit() {
    _notificationsController.add(List.of(notifications));
    _unreadCountController.add(notifications.where((n) => !n.isRead).length);
  }
}

class FakeVocabularyRepository implements VocabularyRepository {
  int dueCount;
  Failure? failure;

  FakeVocabularyRepository(this.dueCount);

  @override
  Future<Either<Failure, Map<String, dynamic>>> getVocabularyStats() async {
    final activeFailure = failure;
    if (activeFailure != null) return Left(activeFailure);
    return Right({'due_for_review': dueCount});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late MemoryNotificationRepository notificationRepository;
  late FakeVocabularyRepository vocabularyRepository;
  late ReviewReminderNotificationSyncService service;

  setUp(() {
    notificationRepository = MemoryNotificationRepository();
    vocabularyRepository = FakeVocabularyRepository(201);
    service = ReviewReminderNotificationSyncService(
      notificationRepository: notificationRepository,
      vocabularyRepository: vocabularyRepository,
      now: () => DateTime(2026, 6, 16, 9),
    );
  });

  tearDown(() {
    notificationRepository.dispose();
  });

  test('adds a vocabulary review notification when words are due', () async {
    await service.sync();

    expect(notificationRepository.notifications, hasLength(1));
    final notification = notificationRepository.notifications.single;
    expect(
      notification.id,
      ReviewReminderNotificationSyncService.notificationId,
    );
    expect(notification.type, NotificationType.vocabularyReviewReminder);
    // Localization is not booted in unit tests, so .tr() falls back to the key.
    expect(notification.title, 'notifications.reviewReminderTitle');
    expect(notification.body, 'notifications.reviewWaitingBody');
    expect(notification.isRead, isFalse);
    expect(notification.data?['route'], '/vocabulary/review');
    expect(notification.data?['due_count'], 201);
    expect(notification.data?['date_key'], '2026-06-16');
  });

  test('removes the review notification when no words are due', () async {
    await service.sync();
    vocabularyRepository.dueCount = 0;

    await service.sync();

    expect(notificationRepository.notifications, isEmpty);
  });

  test('updates same-day reminder without resetting read state', () async {
    await service.sync();
    await notificationRepository.markAsRead(
      ReviewReminderNotificationSyncService.notificationId,
    );
    vocabularyRepository.dueCount = 150;

    await service.sync();

    expect(notificationRepository.notifications, hasLength(1));
    final notification = notificationRepository.notifications.single;
    expect(notification.data?['due_count'], 150);
    expect(notification.isRead, isTrue);
  });

  test('keeps existing reminder when vocabulary stats cannot load', () async {
    await service.sync();
    vocabularyRepository.failure = const NetworkFailure();
    vocabularyRepository.dueCount = 0;

    await service.sync();

    expect(notificationRepository.notifications, hasLength(1));
    expect(
      notificationRepository.notifications.single.data?['due_count'],
      201,
    );
  });
}
