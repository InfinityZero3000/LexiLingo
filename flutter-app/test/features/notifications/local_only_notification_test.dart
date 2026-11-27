import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/notifications/data/datasources/notification_remote_datasource.dart';
import 'package:lexilingo_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:lexilingo_app/features/notifications/domain/services/review_reminder_notification_sync_service.dart';

import 'notification_repository_test.dart' show MockNotificationLocalDataSource;

class _Remote implements NotificationRemoteDataSource {
  final calls = <String>[];

  @override
  Future<void> markAsRead(String id) async => calls.add('read:$id');

  @override
  Future<void> deleteNotification(String id) async => calls.add('delete:$id');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  // The server only knows its own notifications, whose ids are UUIDs; sending it
  // a local reminder's id answered 422 every time.
  test('a local-only notification never reaches the server', () async {
    final remote = _Remote();
    final repository = NotificationRepositoryImpl(
      MockNotificationLocalDataSource(),
      remoteDataSource: remote,
    );
    const local = ReviewReminderNotificationSyncService.notificationId;
    const server = '3f2b6c1e-8a4d-4f7e-9b2a-1c5d7e9f0a3b';

    await repository.markAsRead(local);
    await repository.deleteNotification(local);
    await repository.markAsRead(server);
    await repository.deleteNotification(server);

    expect(remote.calls, ['read:$server', 'delete:$server']);
  });
}
