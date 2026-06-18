import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

class ReviewReminderNotificationSyncService {
  static const notificationId = 'vocabulary_review_due_reminder';
  static const _reviewRoute = '/vocabulary/review';

  final NotificationRepository _notificationRepository;
  final VocabularyRepository _vocabularyRepository;
  final DateTime Function() _now;

  ReviewReminderNotificationSyncService({
    required NotificationRepository notificationRepository,
    required VocabularyRepository vocabularyRepository,
    DateTime Function()? now,
  }) : _notificationRepository = notificationRepository,
       _vocabularyRepository = vocabularyRepository,
       _now = now ?? DateTime.now;

  Future<void> sync() async {
    final result = await _vocabularyRepository.getVocabularyStats();
    final dueCount = result.fold<int?>(
      (_) => null,
      (stats) => _readDueCount(stats['due_for_review']),
    );
    if (dueCount == null) return;

    final existing = await _notificationRepository.getNotificationById(
      notificationId,
    );

    if (dueCount <= 0) {
      if (existing != null) {
        await _notificationRepository.deleteNotification(notificationId);
      }
      return;
    }

    final now = _now();
    final todayKey = _dateKey(now);
    final existingDateKey = existing?.data?['date_key'];
    final sameReminderDay =
        existingDateKey is String && existingDateKey == todayKey;

    final notification = NotificationEntity(
      id: notificationId,
      type: NotificationType.vocabularyReviewReminder,
      title: 'Đến giờ ôn từ vựng',
      body: '$dueCount từ đang đợi bạn ôn tập.',
      timestamp: sameReminderDay ? existing?.timestamp ?? now : now,
      isRead: sameReminderDay ? existing?.isRead ?? false : false,
      data: {
        'route': _reviewRoute,
        'due_count': dueCount,
        'date_key': todayKey,
        'source': 'review_reminder_sync',
      },
      iconIdentifier: 'schedule',
      colorHex: '#2196F3',
    );

    await _notificationRepository.addNotification(notification);
  }

  int _readDueCount(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _dateKey(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
