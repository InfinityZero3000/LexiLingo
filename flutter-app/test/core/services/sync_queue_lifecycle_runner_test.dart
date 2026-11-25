import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/services/background_sync_queue_service.dart';
import 'package:lexilingo_app/core/services/sync_queue_lifecycle_runner.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Online implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

/// Runs the processor once and mirrors the real contract: returning normally
/// means the item is dropped, throwing means it is rescheduled.
class _FakeQueue implements BackgroundSyncQueueService {
  _FakeQueue(this.item);
  final SyncQueueItem item;
  bool dropped = false;
  bool retried = false;

  @override
  Future<void> processPending({
    required String userScope,
    required Future<void> Function(SyncQueueItem item) processor,
    int limit = 50,
  }) async {
    try {
      await processor(item);
      dropped = true;
    } catch (_) {
      retried = true;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncQueueItem _lexiItem() => SyncQueueItem(
  id: 1,
  userScope: 'u1',
  queueType: 'lexi.chat.send.v1',
  payload: {'user_id': 'u1', 'session_id': 'dead-session', 'message': 'hi'},
  idempotencyKey: 'k1',
  retryCount: 0,
  nextRetryAt: DateTime(2026),
);

Future<_FakeQueue> _run(int status, String body) async {
  SharedPreferences.setMockInitialValues({'active_user_id': 'u1'});
  final queue = _FakeQueue(_lexiItem());
  final runner = SyncQueueLifecycleRunner(
    apiClient: ApiClient(
      client: MockClient((_) async => http.Response(body, status)),
      baseUrl: 'http://test',
      networkInfo: _Online(),
    ),
    queueService: queue,
  );
  await runner.processPending(reason: 'test');
  return queue;
}

void main() {
  test(
    'lexi message queued against a missing session is dropped on 404',
    () async {
      final queue = await _run(404, '{"detail":"Session not found"}');
      expect(queue.dropped, isTrue);
      expect(queue.retried, isFalse);
    },
  );

  test('lexi message is still retried on a 400', () async {
    final queue = await _run(400, '{"detail":"bad"}');
    expect(queue.retried, isTrue);
    expect(queue.dropped, isFalse);
  });
}
