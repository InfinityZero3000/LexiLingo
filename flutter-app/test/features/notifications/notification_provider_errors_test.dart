import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';

class _FailingRepository extends Fake implements NotificationRepository {
  final _controller = StreamController<List<NotificationEntity>>.broadcast();
  final _unread = StreamController<int>.broadcast();

  @override
  Stream<List<NotificationEntity>> get notificationsStream =>
      _controller.stream;

  @override
  Stream<int> get unreadCountStream => _unread.stream;

  @override
  Future<List<NotificationGroup>> getGroupedNotifications() async =>
      throw StateError('connection refused: 10.0.0.5:5432');
}

void main() {
  test(
    'a failed load shows a localized message, never the exception',
    () async {
      final repository = _FailingRepository();
      final provider = NotificationProvider(
        repository: repository,
        listenToForegroundFcm: false,
      );

      // The constructor already starts a load; let it finish before asserting.
      await provider.loadNotifications();
      await Future<void>.delayed(Duration.zero);

      expect(provider.errorMessage, 'notifications.failedToLoad');
      expect(provider.errorMessage, isNot(contains('10.0.0.5')));

      provider.dispose();
    },
  );
}
