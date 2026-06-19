import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/services/encrypted_local_cache_service.dart';
import 'package:lexilingo_app/core/services/background_sync_queue_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_stream_event.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';

const _tag = 'LexiChatProvider';

/// Provider for Lexi Chat state management.
///
/// Manages:
///  - Session lifecycle
///  - Message list with optimistic UI
///  - TTS audio playback
///  - Loading / error states
///  - Typing animation state
class LexiChatProvider extends ChangeNotifier {
  final LexiChatRepository repository;
  final AiApiClient _aiClient;
  static const String _savedSessionsKey = 'lexi_saved_sessions';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const int _messagesPageSize = 50;
  static const String _chatNamespace = 'chat';
  final EncryptedLocalCacheService _encryptedCache =
      EncryptedLocalCacheService.instance;
  final BackgroundSyncQueueService _syncQueue =
      BackgroundSyncQueueService.instance;
  StreamSubscription<SyncQueueItem>? _syncQueueSub;

  LexiChatProvider({required this.repository, required AiApiClient aiClient})
    : _aiClient = aiClient {
    _loadSavedSessions();
    _syncQueueSub = _syncQueue.onItemProcessed.listen(_onQueueItemProcessed);
  }

  Future<String> transcribeAudio(Uint8List bytes) async {
    final result = await _aiClient.postMultipart(
      '/stt/transcribe',
      fileField: 'audio',
      fileBytes: bytes,
      filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      timeout: AppConstants.aiOperationTimeout,
    );
    return (result['text'] as String? ?? '').trim();
  }

  // ── State ──────────────────────────────────────────────────────────────────
  LexiSession? _session;
  final List<LexiSessionSummary> _sessions = [];
  final List<LexiMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _isLoadingSessions = false;
  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = false;
  String? _nextMessageCursor;
  bool _isLexiThinking = false;
  bool _isLexiTyping = false;
  bool _isRestoringSession = false;
  String? _error;
  bool _ttsEnabled = true;
  double _ttsSpeed = 1.0;
  String _learnerLevel = 'B1';
  Timer? _typingStageTimer;
  DateTime? _responseStateStartedAt;
  int _requestSequence = 0;

  static const Duration _minResponseIndicatorDuration = Duration(
    milliseconds: 1200,
  );

  // Audio player for Lexi's voice
  final AudioPlayer _ttsPlayer = AudioPlayer();

  // ── Getters ────────────────────────────────────────────────────────────────
  LexiSession? get session => _session;
  List<LexiSessionSummary> get sessions => List.unmodifiable(_sessions);
  List<LexiMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  bool get isLoadingSessions => _isLoadingSessions;
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get isLexiThinking => _isLexiThinking;
  bool get isLexiTyping => _isLexiTyping;
  bool get isLexiResponding => _isLexiThinking || _isLexiTyping;
  String? get error => _error;
  bool get hasSession => _session != null;
  bool get ttsEnabled => _ttsEnabled;
  double get ttsSpeed => _ttsSpeed;

  String get ttsSpeedLabel {
    if (_ttsSpeed == 1.0) return '1.0x';
    if (_ttsSpeed == 1.25) return '1.25x';
    if (_ttsSpeed == 1.5) return '1.5x';
    if (_ttsSpeed == 0.75) return '0.75x';
    return '${_ttsSpeed}x';
  }

  bool _isUnauthorizedError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('unauthorized') ||
        normalized.contains('status 401') ||
        normalized.contains('401');
  }

  String get learnerLevel => _learnerLevel;

  // ── Session ────────────────────────────────────────────────────────────────
  Future<void> startSession(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _session = await repository.createSession(userId: userId);
      _upsertSessionSummary(
        LexiSessionSummary(
          sessionId: _session!.sessionId,
          userId: userId,
          title: _session!.title ?? _buildSessionTitle(),
          createdAt: _session!.createdAt,
          updatedAt: _session!.updatedAt ?? DateTime.now(),
        ),
      );
      _messages.clear();
      _isLoadingMoreMessages = false;
      _hasMoreMessages = false;
      _nextMessageCursor = null;

      // Add Lexi's greeting
      _messages.add(
        LexiMessage(
          id: 'greeting',
          role: 'assistant',
          content:
              "Squawk! Hey there, adventurer! I'm Lexi, your English buddy. "
              "Let's go on a learning adventure together!\n\n"
              "You can type or speak — I'll help you practice English. "
              "What would you like to talk about?",
          timestamp: DateTime.now(),
        ),
      );

      _isLoading = false;
      unawaited(syncSessions(userId));
      notifyListeners();
    } catch (e) {
      _error = 'Failed to start session: $e';
      if (_isUnauthorizedError(e)) {
        _error = 'Your login session expired. Please sign in again.';
      }
      _isLoading = false;
      logError(_tag, _error!);
      notifyListeners();
    }
  }

  Future<void> createNewSession(String userId) async {
    await startSession(userId);
  }

  Future<void> restoreLatestSession(String userId) async {
    if (_isRestoringSession || _session != null) return;

    _isRestoringSession = true;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await syncSessions(userId);

      if (_sessions.isNotEmpty) {
        await selectSession(_sessions.first);
      } else {
        await startSession(userId);
      }
    } catch (e) {
      _error = 'Failed to restore session: $e';
      _isLoading = false;
      logWarn(_tag, _error!);
      notifyListeners();
    } finally {
      _isRestoringSession = false;
    }
  }

  Future<void> selectSession(LexiSessionSummary summary) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    var restoredFromCache = false;

    try {
      _session = LexiSession(
        sessionId: summary.sessionId,
        userId: summary.userId,
        createdAt: summary.createdAt,
        title: summary.title,
        updatedAt: summary.updatedAt,
        messageCount: summary.messageCount,
      );

      final cachedPage = await _getCachedFirstPage(summary);
      if (cachedPage != null && cachedPage.messages.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(cachedPage.messages);
        _hasMoreMessages = cachedPage.hasMore;
        _nextMessageCursor = cachedPage.nextCursor;
        _isLoading = false;
        restoredFromCache = true;
        notifyListeners();
      }

      final page = await repository.getMessagesPaged(
        sessionId: summary.sessionId,
        limit: _messagesPageSize,
      );

      var loaded = page.messages;
      _hasMoreMessages = page.hasMore;
      _nextMessageCursor = page.nextCursor;

      if (loaded.isEmpty && summary.messageCount > 0) {
        // Fallback for older servers that don't support paged contract yet.
        loaded = await repository.getMessages(sessionId: summary.sessionId);
        _hasMoreMessages = false;
        _nextMessageCursor = null;
      }

      _messages
        ..clear()
        ..addAll(loaded);

      await _cacheFirstPage(
        summary,
        messages: loaded,
        hasMore: _hasMoreMessages,
        nextCursor: _nextMessageCursor,
      );

      if (loaded.isEmpty) {
        if (summary.messageCount > 0) {
          _error =
              'Session history is temporarily unavailable. You can continue chatting.';
        }
        _messages.add(
          LexiMessage(
            id: 'greeting',
            role: 'assistant',
            content:
                "Squawk! Hey there, adventurer! I'm Lexi, your English buddy. "
                "Let's go on a learning adventure together!\n\n"
                "You can type or speak — I'll help you practice English. "
                "What would you like to talk about?",
            timestamp: DateTime.now(),
          ),
        );
      }

      _touchSession(summary.sessionId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (restoredFromCache) {
        _isLoading = false;
        notifyListeners();
        return;
      }

      final err = e.toString().toLowerCase();
      if (err.contains('404') || err.contains('not found')) {
        _sessions.removeWhere((s) => s.sessionId == summary.sessionId);
        await _saveSessions();
        await startSession(summary.userId);
        _error = 'Session expired on server. Started a new one.';
        return;
      }

      _error = 'Failed to load session: $e';
      if (_isUnauthorizedError(e)) {
        _error = 'Your login session expired. Please sign in again.';
      }
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadOlderMessages() async {
    if (_session == null || _isLoadingMoreMessages || !_hasMoreMessages) return;

    _isLoadingMoreMessages = true;
    notifyListeners();

    try {
      final page = await repository.getMessagesPaged(
        sessionId: _session!.sessionId,
        limit: _messagesPageSize,
        cursor: _nextMessageCursor,
      );

      if (page.messages.isNotEmpty) {
        _messages.insertAll(0, page.messages);
        await _cacheCurrentMessages();
      }
      _hasMoreMessages = page.hasMore;
      _nextMessageCursor = page.nextCursor;
    } catch (e) {
      _error = 'Failed to load older messages: $e';
      logWarn(_tag, _error!);
    } finally {
      _isLoadingMoreMessages = false;
      notifyListeners();
    }
  }

  Future<void> renameSession(String sessionId, String title) async {
    final idx = _sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx == -1) return;
    await repository.renameSession(sessionId: sessionId, title: title.trim());
    _sessions[idx] = _sessions[idx].copyWith(title: title.trim());
    await _saveSessions();
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await repository.deleteSession(sessionId: sessionId);
    _sessions.removeWhere((s) => s.sessionId == sessionId);
    if (_session?.sessionId == sessionId) {
      _session = null;
      _messages.clear();
      _isLoadingMoreMessages = false;
      _hasMoreMessages = false;
      _nextMessageCursor = null;
    }
    await _saveSessions();
    notifyListeners();
  }

  // ── Send Message ───────────────────────────────────────────────────────────
  Future<void> sendMessage(String text, {String? userId}) async {
    if (text.trim().isEmpty || _isSending) return;

    final uid = userId ?? 'demo_user';
    if (_session == null) {
      await startSession(uid);
    }
    final sessionId = _session?.sessionId ?? '';
    final requestId = _buildRequestId(uid, sessionId);

    // Optimistic: add user message immediately
    final userMsg = LexiMessage(
      id: requestId,
      role: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
      syncStatus: 'pending_sync',
      clientRequestId: requestId,
    );
    _messages.add(userMsg);
    _isSending = true;
    _beginLexiResponseState();
    _error = null;
    notifyListeners();

    try {
      final response = await repository.sendMessage(
        userId: uid,
        sessionId: sessionId,
        message: text.trim(),
        enableTts: _ttsEnabled,
        learnerLevel: _learnerLevel,
        idempotencyKey: requestId,
      );

      final idx = _messages.indexWhere((m) => m.id == requestId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(syncStatus: 'synced');
      }

      _messages.add(response);
      await _cacheCurrentMessages();
      _touchSession(sessionId, messageDelta: 2);
      await _endLexiResponseState();
      _isSending = false;
      notifyListeners();

      // Auto-play TTS if available
      if (_ttsEnabled && response.hasAudio) {
        await _playTtsAudio(response.audioBase64!);
      }
    } catch (e) {
      await _endLexiResponseState();
      _isSending = false;
      if (_isUnauthorizedError(e)) {
        _error = 'Your login session expired. Please sign in again.';
        logError(_tag, _error!);
        notifyListeners();
        return;
      }
      _error = 'You are offline. Message queued for sync.';
      logError(_tag, _error!);

      await _enqueuePendingLexiMessage(
        userId: uid,
        sessionId: sessionId,
        message: text.trim(),
        idempotencyKey: requestId,
      );
      await _cacheCurrentMessages();
      notifyListeners();
    }
  }

  Future<void> _enqueuePendingLexiMessage({
    required String userId,
    required String sessionId,
    required String message,
    required String idempotencyKey,
  }) async {
    final userScope = await UserScopeService.getScopeOrDefault();
    if (userScope == 'anonymous') {
      return;
    }

    await _syncQueue.enqueue(
      userScope: userScope,
      queueType: 'lexi.chat.send.v1',
      idempotencyKey: idempotencyKey,
      payload: {
        'user_id': userId,
        'session_id': sessionId,
        'message': message,
        'input_type': 'text',
        'enable_tts': _ttsEnabled,
        'learner_level': _learnerLevel,
      },
    );
  }

  String _buildRequestId(String userId, String sessionId) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final sequence = _nextRequestSequence();
    final userPart = _requestIdPart(userId, fallback: 'user');
    final sessionPart = _requestIdPart(sessionId, fallback: 'session');
    return 'lexi-$userPart-$sessionPart-$timestamp-$sequence';
  }

  int _nextRequestSequence() {
    _requestSequence = (_requestSequence + 1) & 0x3fffffff;
    return _requestSequence;
  }

  String _requestIdPart(String value, {required String fallback}) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) return fallback;
    return normalized.length <= 48 ? normalized : normalized.substring(0, 48);
  }

  // ── Send Message (streaming / typewriter effect) ───────────────────────────

  /// Sends a message and shows the AI response word-by-word (typewriter effect).
  ///
  /// Works by:
  ///   1. Adding an optimistic user message.
  ///   2. Inserting a placeholder assistant message with [syncStatus] = 'streaming'.
  ///   3. Appending each [LexiStreamChunk] word to the placeholder's content.
  ///   4. Replacing the placeholder with the final [LexiMessage] on [LexiStreamDone].
  ///   5. Falling back to the regular [sendMessage] on streaming errors.
  Future<void> sendMessageStreaming(String text, {String? userId}) async {
    if (text.trim().isEmpty || _isSending) return;

    final uid = userId ?? 'demo_user';
    if (_session == null) {
      await startSession(uid);
    }
    final sessionId = _session?.sessionId ?? '';
    final requestId = _buildRequestId(uid, sessionId);
    final placeholderId = 'stream_$requestId';

    // Optimistic: user message
    final userMsg = LexiMessage(
      id: requestId,
      role: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
      syncStatus: 'pending_sync',
      clientRequestId: requestId,
    );
    _messages.add(userMsg);

    // Streaming placeholder for the assistant response
    _messages.add(
      LexiMessage(
        id: placeholderId,
        role: 'assistant',
        content: '',
        timestamp: DateTime.now(),
        syncStatus: 'streaming',
      ),
    );

    _isSending = true;
    _isLexiThinking = true;
    _isLexiTyping = false;
    _error = null;
    notifyListeners();

    var receivedDone = false;

    try {
      await for (final event in repository.sendMessageStream(
        userId: uid,
        sessionId: sessionId,
        message: text.trim(),
        enableTts: _ttsEnabled,
        learnerLevel: _learnerLevel,
      )) {
        switch (event) {
          case LexiStreamThinking():
            _isLexiThinking = true;
            _isLexiTyping = false;
            notifyListeners();

          case LexiStreamChunk(:final text):
            _isLexiThinking = false;
            _isLexiTyping = true;
            final idx = _messages.indexWhere((m) => m.id == placeholderId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(
                content: _messages[idx].content + text,
              );
              notifyListeners();
            }

          case LexiStreamDone(
            :final messageId,
            :final fullText,
            :final corrections,
            :final linkedConcepts,
            :final vietnameseHint,
            :final scores,
            :final audioBase64,
          ):
            receivedDone = true;
            final idx = _messages.indexWhere((m) => m.id == placeholderId);
            if (idx != -1) {
              final accumulated = _messages[idx].content.trim();
              final serverText = fullText?.trim() ?? '';
              // Prefer server-sanitized text (strips <think> blocks, properly formatted).
              // Fall back to raw accumulated chunks only when server text is absent.
              final finalContent = serverText.isNotEmpty
                  ? serverText
                  : (accumulated.isNotEmpty
                      ? accumulated
                      : 'Squawk! Something went quiet. Can you ask that again?');
              _messages[idx] = LexiMessage(
                id: messageId.isNotEmpty ? messageId : placeholderId,
                role: 'assistant',
                content: finalContent,
                timestamp: DateTime.now(),
                audioBase64: audioBase64,
                corrections: corrections,
                linkedConcepts: linkedConcepts,
                vietnameseHint: vietnameseHint,
                scores: scores,
                syncStatus: 'synced',
              );
            }

            // Mark user message as synced
            final userIdx = _messages.indexWhere((m) => m.id == requestId);
            if (userIdx != -1) {
              _messages[userIdx] = _messages[userIdx].copyWith(
                syncStatus: 'synced',
              );
            }

            await _cacheCurrentMessages();
            _touchSession(sessionId, messageDelta: 2);
            _isLexiThinking = false;
            _isLexiTyping = false;
            _isSending = false;
            notifyListeners();

            if (_ttsEnabled && audioBase64 != null && audioBase64.isNotEmpty) {
              await _playTtsAudio(audioBase64);
            }
          // storyContext is returned by the server for context continuity; no local storage needed.
          case LexiStreamError(:final error):
            logError(_tag, 'sendMessageStreaming error event: $error');
            await _retryNonStreamingSend(
              text: text,
              userId: uid,
              requestId: requestId,
              placeholderId: placeholderId,
              reason: error,
            );
            return;
        }
      }

      if (!receivedDone) {
        await _handleIncompleteStream(
          text: text,
          userId: uid,
          sessionId: sessionId,
          requestId: requestId,
          placeholderId: placeholderId,
        );
      }
    } catch (e) {
      logError(_tag, 'sendMessageStreaming exception: $e');
      await _retryNonStreamingSend(
        text: text,
        userId: uid,
        requestId: requestId,
        placeholderId: placeholderId,
        reason: e.toString(),
      );
    }
  }

  Future<void> _handleIncompleteStream({
    required String text,
    required String userId,
    required String sessionId,
    required String requestId,
    required String placeholderId,
  }) async {
    final idx = _messages.indexWhere((m) => m.id == placeholderId);
    final partialContent = idx == -1 ? '' : _messages[idx].content.trim();

    if (partialContent.isEmpty) {
      await _retryNonStreamingSend(
        text: text,
        userId: userId,
        requestId: requestId,
        placeholderId: placeholderId,
        reason: 'stream closed before sending a response',
      );
      return;
    }

    if (idx != -1) {
      _messages[idx] = _messages[idx].copyWith(syncStatus: 'synced');
    }

    final userIdx = _messages.indexWhere((m) => m.id == requestId);
    if (userIdx != -1) {
      _messages[userIdx] = _messages[userIdx].copyWith(syncStatus: 'synced');
    }

    _isLexiThinking = false;
    _isLexiTyping = false;
    _isSending = false;
    await _cacheCurrentMessages();
    _touchSession(sessionId, messageDelta: 2);
    logWarn(_tag, 'Lexi stream closed without a done event; kept content');
    notifyListeners();
  }

  Future<void> _retryNonStreamingSend({
    required String text,
    required String userId,
    required String requestId,
    required String placeholderId,
    required String reason,
  }) async {
    logWarn(_tag, 'Retry Lexi message without streaming: $reason');
    _messages.removeWhere((m) => m.id == placeholderId);
    _messages.removeWhere((m) => m.id == requestId);
    _isLexiThinking = false;
    _isLexiTyping = false;
    _isSending = false;

    if (_isUnauthorizedError(reason)) {
      _error = 'Your login session expired. Please sign in again.';
      logError(_tag, _error!);
      notifyListeners();
      return;
    }

    notifyListeners();
    await sendMessage(text, userId: userId);
  }

  Future<void> sendVoiceMessage(String audioBase64, {String? userId}) async {
    if (_isSending) return;

    final uid = userId ?? 'demo_user';
    if (_session == null) {
      await startSession(uid);
    }
    final sessionId = _session?.sessionId ?? '';

    _isSending = true;
    _beginLexiResponseState();
    _error = null;

    // Show recording indicator
    _messages.add(
      LexiMessage(
        id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
        role: 'user',
        content: 'Voice message...',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();

    try {
      final response = await repository.sendMessage(
        userId: uid,
        sessionId: sessionId,
        message: 'voice_input',
        inputType: 'voice',
        audioBase64: audioBase64,
        enableTts: _ttsEnabled,
        learnerLevel: _learnerLevel,
      );

      _messages.add(response);
      await _cacheCurrentMessages();
      _touchSession(sessionId, messageDelta: 2);
      await _endLexiResponseState();
      _isSending = false;
      notifyListeners();

      if (_ttsEnabled && response.hasAudio) {
        await _playTtsAudio(response.audioBase64!);
      }
    } catch (e) {
      await _endLexiResponseState();
      _isSending = false;
      if (_isUnauthorizedError(e)) {
        _error = 'Your login session expired. Please sign in again.';
        logError(_tag, _error!);
        notifyListeners();
        return;
      }
      _error = 'Voice processing failed: $e';
      logError(_tag, _error!);
      notifyListeners();
    }
  }

  void _beginLexiResponseState() {
    _typingStageTimer?.cancel();
    _isLexiThinking = true;
    _isLexiTyping = false;
    _responseStateStartedAt = DateTime.now();

    // Transition to typing state if request takes longer.
    _typingStageTimer = Timer(const Duration(milliseconds: 700), () {
      if (!_isSending) return;
      _isLexiThinking = false;
      _isLexiTyping = true;
      notifyListeners();
    });
  }

  Future<void> _endLexiResponseState() async {
    final startedAt = _responseStateStartedAt;
    if (startedAt != null) {
      final elapsed = DateTime.now().difference(startedAt);
      final remaining = _minResponseIndicatorDuration - elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    }

    _typingStageTimer?.cancel();
    _isLexiThinking = false;
    _isLexiTyping = false;
    _responseStateStartedAt = null;
  }

  // ── TTS Playback ──────────────────────────────────────────────────────────
  Future<void> _playTtsAudio(String base64Audio) async {
    try {
      final bytes = base64Decode(base64Audio);
      final uri = Uri.dataFromBytes(bytes, mimeType: 'audio/mpeg');
      await _ttsPlayer.setUrl(uri.toString());
      await _ttsPlayer.setSpeed(_ttsSpeed);
      await _ttsPlayer.play();
    } catch (e) {
      logWarn(_tag, 'TTS playback failed: $e');
    }
  }

  /// Replay audio of a specific message.
  Future<void> replayAudio(LexiMessage message) async {
    if (message.hasAudio) {
      await _playTtsAudio(message.audioBase64!);
    }
  }

  Future<void> _onQueueItemProcessed(SyncQueueItem item) async {
    if (item.queueType != 'lexi.chat.send.v1') return;

    final sessionId = item.payload['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty) return;
    if (_session?.sessionId != sessionId) return;

    final idx = _messages.indexWhere(
      (m) => m.clientRequestId == item.idempotencyKey && m.isPendingSync,
    );
    if (idx == -1) return;

    _messages[idx] = _messages[idx].copyWith(syncStatus: 'synced');
    await _cacheCurrentMessages();
    notifyListeners();
  }

  // ── Settings ──────────────────────────────────────────────────────────────
  void toggleTts() {
    _ttsEnabled = !_ttsEnabled;
    if (!_ttsEnabled) {
      _ttsPlayer.stop();
    }
    notifyListeners();
  }

  Future<void> cycleTtsSpeed() async {
    if (_ttsSpeed == 1.0) {
      _ttsSpeed = 1.25;
    } else if (_ttsSpeed == 1.25) {
      _ttsSpeed = 1.5;
    } else if (_ttsSpeed == 1.5) {
      _ttsSpeed = 0.75;
    } else {
      _ttsSpeed = 1.0;
    }
    await _ttsPlayer.setSpeed(_ttsSpeed);
    notifyListeners();
  }

  void setLearnerLevel(String level) {
    _learnerLevel = level;
    notifyListeners();
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────
  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncQueueSub?.cancel();
    _typingStageTimer?.cancel();
    _ttsPlayer.dispose();
    super.dispose();
  }

  String _buildSessionTitle() {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final dd = now.day.toString().padLeft(2, '0');
    final mo = now.month.toString().padLeft(2, '0');
    return 'Lexi $hh:$mm $dd/$mo';
  }

  void _upsertSessionSummary(LexiSessionSummary summary) {
    _sessions.removeWhere((s) => s.sessionId == summary.sessionId);
    _sessions.insert(0, summary);
    unawaited(_saveSessions());
  }

  void _touchSession(String sessionId, {int messageDelta = 0}) {
    final idx = _sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx == -1) return;
    final current = _sessions.removeAt(idx);
    final item = current.copyWith(
      updatedAt: DateTime.now(),
      messageCount: (current.messageCount + messageDelta)
          .clamp(0, 1 << 30)
          .toInt(),
    );
    _sessions.insert(0, item);
    unawaited(_saveSessions());
  }

  Future<void> syncSessions(String userId) async {
    try {
      final remote = await repository.getSessions(userId: userId);
      if (remote.isEmpty) return;

      _sessions
        ..clear()
        ..addAll(
          remote.map(
            (s) => LexiSessionSummary(
              sessionId: s.sessionId,
              userId: s.userId,
              title: s.title ?? 'Lexi Chat',
              createdAt: s.createdAt,
              updatedAt: s.updatedAt ?? s.createdAt,
              messageCount: s.messageCount ?? 0,
            ),
          ),
        );
      await _saveSessions();
      notifyListeners();
    } catch (e) {
      logWarn(_tag, 'syncSessions failed: $e');
    }
  }

  Future<void> _loadSavedSessions() async {
    _isLoadingSessions = true;
    notifyListeners();

    try {
      final rawString = await _secureStorage.read(key: _savedSessionsKey);
      if (rawString == null || rawString.isEmpty) {
        _isLoadingSessions = false;
        notifyListeners();
        return;
      }
      final raw = (jsonDecode(rawString) as List).cast<dynamic>();
      _sessions
        ..clear()
        ..addAll(
          raw
              .map(
                (e) =>
                    LexiSessionSummary.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList(),
        );
    } catch (e) {
      logWarn(_tag, 'Failed to load saved Lexi sessions: $e');
    }

    _isLoadingSessions = false;
    notifyListeners();
  }

  Future<void> _saveSessions() async {
    try {
      final raw = jsonEncode(_sessions.map((e) => e.toJson()).toList());
      await _secureStorage.write(key: _savedSessionsKey, value: raw);
    } catch (e) {
      logWarn(_tag, 'Failed to save Lexi sessions: $e');
    }
  }

  String _chatFirstPageCacheKey(String sessionId) =>
      'chat:session:$sessionId:page:first';

  Future<_CachedChatPage?> _getCachedFirstPage(
    LexiSessionSummary summary,
  ) async {
    final raw = await _encryptedCache.getMap(
      userScope: summary.userId,
      namespace: _chatNamespace,
      key: _chatFirstPageCacheKey(summary.sessionId),
      enforceTtl: true,
    );
    if (raw == null) return null;
    return _CachedChatPage.fromJson(raw);
  }

  Future<void> _cacheCurrentMessages() async {
    if (_session == null) return;

    await _cacheFirstPage(
      LexiSessionSummary(
        sessionId: _session!.sessionId,
        userId: _session!.userId,
        title: _session!.title ?? _buildSessionTitle(),
        createdAt: _session!.createdAt,
        updatedAt: _session!.updatedAt ?? DateTime.now(),
        messageCount: _messages.length,
      ),
      messages: _messages,
      hasMore: _hasMoreMessages,
      nextCursor: _nextMessageCursor,
    );
  }

  Future<void> _cacheFirstPage(
    LexiSessionSummary summary, {
    required List<LexiMessage> messages,
    required bool hasMore,
    required String? nextCursor,
  }) async {
    final payload = {
      'messages': messages
          .map(
            (m) => {
              'id': m.id,
              'role': m.role,
              'content': m.content,
              'timestamp': m.timestamp.toIso8601String(),
              'audio_base64': m.audioBase64,
              'vietnamese_hint': m.vietnameseHint,
              'linked_concepts': m.linkedConcepts,
              'scores': m.scores,
              'sync_status': m.syncStatus,
              'client_request_id': m.clientRequestId,
              'corrections': m.corrections
                  .map(
                    (c) => {
                      'error_span': c.errorSpan,
                      'correction': c.correction,
                      'error_type': c.errorType,
                      'explanation': c.explanation,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
      'has_more': hasMore,
      'next_cursor': nextCursor,
      'message_count': messages.length,
    };

    await _encryptedCache.putJson(
      userScope: summary.userId,
      namespace: _chatNamespace,
      key: _chatFirstPageCacheKey(summary.sessionId),
      value: payload,
    );
  }
}

class _CachedChatPage {
  final List<LexiMessage> messages;
  final bool hasMore;
  final String? nextCursor;

  const _CachedChatPage({
    required this.messages,
    required this.hasMore,
    required this.nextCursor,
  });

  factory _CachedChatPage.fromJson(Map<String, dynamic> json) {
    final rawMessages = (json['messages'] as List<dynamic>? ?? const []);
    final messages = rawMessages.map((entry) {
      final m = Map<String, dynamic>.from(entry as Map);
      final corrections = (m['corrections'] as List<dynamic>? ?? const [])
          .map(
            (c) => LexiCorrection(
              errorSpan: (c as Map)['error_span']?.toString() ?? '',
              correction: c['correction']?.toString() ?? '',
              errorType: c['error_type']?.toString() ?? '',
              explanation: c['explanation']?.toString() ?? '',
            ),
          )
          .toList();
      return LexiMessage(
        id: m['id']?.toString() ?? '',
        role: m['role']?.toString() ?? 'assistant',
        content: m['content']?.toString() ?? '',
        timestamp:
            DateTime.tryParse(m['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        audioBase64: m['audio_base64']?.toString(),
        corrections: corrections,
        linkedConcepts: (m['linked_concepts'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
        vietnameseHint: m['vietnamese_hint']?.toString(),
        scores: m['scores'] is Map
            ? Map<String, dynamic>.from(m['scores'] as Map)
            : null,
        syncStatus: m['sync_status']?.toString() ?? 'synced',
        clientRequestId: m['client_request_id']?.toString(),
      );
    }).toList();

    return _CachedChatPage(
      messages: messages,
      hasMore: json['has_more'] as bool? ?? false,
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

class LexiSessionSummary {
  final String sessionId;
  final String userId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int messageCount;

  const LexiSessionSummary({
    required this.sessionId,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
  });

  LexiSessionSummary copyWith({
    String? title,
    DateTime? updatedAt,
    int? messageCount,
  }) {
    return LexiSessionSummary(
      sessionId: sessionId,
      userId: userId,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messageCount: messageCount ?? this.messageCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'user_id': userId,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'message_count': messageCount,
    };
  }

  factory LexiSessionSummary.fromJson(Map<String, dynamic> json) {
    return LexiSessionSummary(
      sessionId: json['session_id'] ?? '',
      userId: json['user_id'] ?? '',
      title: json['title'] ?? 'Lexi Chat',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      messageCount: (json['message_count'] as num?)?.toInt() ?? 0,
    );
  }
}
