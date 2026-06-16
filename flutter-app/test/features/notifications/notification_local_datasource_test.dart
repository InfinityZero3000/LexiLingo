import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/notifications/data/datasources/notification_local_datasource.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  NotificationEntity createNotification({
    required String id,
    required String body,
    required DateTime timestamp,
  }) {
    return NotificationEntity(
      id: id,
      type: NotificationType.vocabularyReviewReminder,
      title: 'Đến giờ ôn từ vựng',
      body: body,
      timestamp: timestamp,
      data: const {'route': '/vocabulary/review'},
      iconIdentifier: 'schedule',
      colorHex: '#2196F3',
    );
  }

  test('addNotification upserts by id instead of duplicating', () async {
    final dataSource = NotificationLocalDataSourceImpl();

    await dataSource.addNotification(
      createNotification(
        id: 'vocabulary_review_due_reminder',
        body: '201 từ đang đợi bạn ôn tập.',
        timestamp: DateTime(2026, 6, 16, 9),
      ),
    );
    await dataSource.addNotification(
      createNotification(
        id: 'vocabulary_review_due_reminder',
        body: '150 từ đang đợi bạn ôn tập.',
        timestamp: DateTime(2026, 6, 16, 10),
      ),
    );

    final notifications = await dataSource.getNotifications();

    expect(notifications, hasLength(1));
    expect(notifications.single.body, '150 từ đang đợi bạn ôn tập.');
  });
}
