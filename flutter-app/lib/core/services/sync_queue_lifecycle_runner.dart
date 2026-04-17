import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../network/api_client.dart';
import '../utils/app_logger.dart';
import 'background_sync_queue_service.dart';
import 'encrypted_local_cache_service.dart';
import 'user_scope_service.dart';

const _tag = 'SyncQueueLifecycleRunner';

/// Runs pending background sync jobs when app resumes or network reconnects.
class SyncQueueLifecycleRunner {
  SyncQueueLifecycleRunner({
    required ApiClient apiClient,
    Connectivity? connectivity,
    BackgroundSyncQueueService? queueService,
    EncryptedLocalCacheService? encryptedCache,
  }) : _apiClient = apiClient,
       _connectivity = connectivity ?? Connectivity(),
       _queueService = queueService ?? BackgroundSyncQueueService.instance,
       _encryptedCache = encryptedCache ?? EncryptedLocalCacheService.instance;

  final ApiClient _apiClient;
  final Connectivity _connectivity;
  final BackgroundSyncQueueService _queueService;
  final EncryptedLocalCacheService _encryptedCache;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _started = false;
  bool _isProcessing = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) {
        unawaited(processPending(reason: 'connectivity-restored'));
      }
    });

    await processPending(reason: 'runner-start');
  }

  Future<void> stop() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _started = false;
  }

  Future<void> onAppResumed() async {
    await processPending(reason: 'app-resumed');
  }

  Future<void> processPending({required String reason}) async {
    if (_isProcessing) return;

    final userScope = await UserScopeService.getActiveUserId();
    if (userScope == null || userScope.isEmpty) {
      return;
    }

    _isProcessing = true;
    try {
      logDebug(_tag, 'Processing queue for $userScope ($reason)');
      await _queueService.processPending(
        userScope: userScope,
        processor: (item) async {
          switch (item.queueType) {
            case 'vocab.add_word.v1':
              await _apiClient.post(
                '/vocabulary/collection/quick-save',
                body: {
                  'word': item.payload['word'],
                  'source_type': item.payload['source_type'] ?? 'manual',
                  if (item.payload['definition'] != null)
                    'definition': item.payload['definition'],
                  if (item.payload['context_sentence'] != null)
                    'context_sentence': item.payload['context_sentence'],
                },
                headers: {'X-Idempotency-Key': item.idempotencyKey},
              );
              return;
            case 'lexi.chat.send.v1':
              await _apiClient.post(
                '/lexi/chat',
                body: {
                  'user_id': item.payload['user_id'],
                  'session_id': item.payload['session_id'],
                  'message': item.payload['message'],
                  'input_type': item.payload['input_type'] ?? 'text',
                  'enable_tts': item.payload['enable_tts'] ?? true,
                  'learner_level': item.payload['learner_level'] ?? 'B1',
                  if (item.payload['story_context'] != null)
                    'story_context': item.payload['story_context'],
                },
                headers: {'X-Idempotency-Key': item.idempotencyKey},
              );
              await _markLexiMessageSynced(
                userScope: userScope,
                sessionId: item.payload['session_id']?.toString() ?? '',
                idempotencyKey: item.idempotencyKey,
              );
              return;
            default:
              // Unknown item type: leave queued for later processor support.
              throw UnsupportedError('Unsupported queue type: ${item.queueType}');
          }
        },
      );
    } catch (e) {
      logWarn(_tag, 'Queue processing failed: $e');
    } finally {
      _isProcessing = false;
    }
  }

  String _chatFirstPageCacheKey(String sessionId) =>
      'chat:session:$sessionId:page:first';

  Future<void> _markLexiMessageSynced({
    required String userScope,
    required String sessionId,
    required String idempotencyKey,
  }) async {
    if (sessionId.isEmpty || idempotencyKey.isEmpty) return;

    final raw = await _encryptedCache.getMap(
      userScope: userScope,
      namespace: 'chat',
      key: _chatFirstPageCacheKey(sessionId),
      enforceTtl: false,
    );
    if (raw == null) return;

    final rawMessages = raw['messages'];
    if (rawMessages is! List) return;

    var changed = false;
    final updatedMessages = rawMessages.map((entry) {
      if (entry is! Map) return entry;
      final msg = Map<String, dynamic>.from(entry as Map<dynamic, dynamic>);
      if (msg['client_request_id']?.toString() == idempotencyKey &&
          msg['sync_status']?.toString() == 'pending_sync') {
        changed = true;
        msg['sync_status'] = 'synced';
      }
      return msg;
    }).toList();

    if (!changed) return;

    final payload = Map<String, dynamic>.from(raw);
    payload['messages'] = updatedMessages;
    await _encryptedCache.putJson(
      userScope: userScope,
      namespace: 'chat',
      key: _chatFirstPageCacheKey(sessionId),
      value: payload,
    );
  }
}
