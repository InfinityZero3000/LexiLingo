import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/background_sync_queue_service.dart';
import 'package:lexilingo_app/features/offline/presentation/pages/offline_sync_center_page.dart';

void main() {
  group('OfflineSyncSnapshot', () {
    test('reports active user scope when user id is present', () {
      const snapshot = OfflineSyncSnapshot(
        isOnline: true,
        cacheSize: 3,
        cacheCountsByType: {'news': 2, 'book': 1},
        activeUserScope: 'user-123',
        queueSummary: SyncQueueSummary.unsupported,
      );

      expect(snapshot.hasActiveUser, isTrue);
    });

    test('reports no active user scope when user id is missing', () {
      const snapshot = OfflineSyncSnapshot(
        isOnline: false,
        cacheSize: 0,
        cacheCountsByType: {},
        activeUserScope: null,
        queueSummary: SyncQueueSummary.unsupported,
      );

      expect(snapshot.hasActiveUser, isFalse);
    });
  });
}
