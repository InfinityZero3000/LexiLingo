import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';

class _MemoryRepository extends Fake implements NotificationRepository {
  final items = <String, NotificationEntity>{};

  @override
  Stream<List<NotificationEntity>> get notificationsStream =>
      const Stream.empty();

  @override
  Stream<int> get unreadCountStream => const Stream.empty();

  @override
  Future<List<NotificationGroup>> getGroupedNotifications() async => [];

  @override
  Future<List<NotificationEntity>> getNotifications() async =>
      items.values.toList();

  @override
  Future<int> getUnreadCount() async =>
      items.values.where((n) => !n.isRead).length;

  @override
  Future<NotificationEntity?> getNotificationById(String id) async => items[id];

  @override
  Future<void> addNotification(NotificationEntity notification) async =>
      items[notification.id] = notification;

  @override
  Future<void> deleteNotification(String id) async => items.remove(id);
}

void main() {
  test('an unverified account has one verify entry; verifying removes it', () async {
    final repo = _MemoryRepository();
    final provider = NotificationProvider(
      repository: repo,
      listenToForegroundFcm: false,
    );
    const id = NotificationProvider.emailVerificationId;

    await provider.syncEmailVerification(email: 'a@example.com', verified: false);
    expect(repo.items[id]?.destinationRoute, '/profile/edit');

    // Read, then synced again on the next launch: it must not turn new again.
    repo.items[id] = repo.items[id]!.copyWith(isRead: true);
    await provider.syncEmailVerification(email: 'a@example.com', verified: false);
    expect(repo.items[id]!.isRead, isTrue);
    expect(repo.items.length, 1);

    await provider.syncEmailVerification(email: 'a@example.com', verified: true);
    expect(repo.items, isEmpty);

    provider.dispose();
  });

  test('the welcome gift is recognised from the server row and from a push', () {
    final row = NotificationEntity.fromBackend({
      'id': 'n1',
      'type': 'starter_reward',
      'title': 'Welcome gift',
      'body': '100 Gems have been added to your wallet.',
      'data': {'reward_key': 'new_user_starter_gems_v1', 'gems': 100},
    });
    final push = NotificationEntity.fromFcm(
      id: 'n2',
      title: 'Welcome gift',
      body: '',
      data: {'type': 'starter_reward', 'gems': '100'},
    );
    final other = NotificationEntity.fromBackend({
      'id': 'n3',
      'type': 'system',
      'title': 't',
      'data': {'route': '/'},
    });

    expect(row.isStarterReward, isTrue);
    expect(push.isStarterReward, isTrue);
    expect(other.isStarterReward, isFalse);
  });
}
