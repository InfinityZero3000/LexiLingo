import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
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
  static const String _savedSessionsKey = 'lexi_saved_sessions';
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  LexiChatProvider({required this.repository}) {
    _loadSavedSessions();
  }

  // ── State ──────────────────────────────────────────────────────────────────
  LexiSession? _session;
  final List<LexiSessionSummary> _sessions = [];
  final List<LexiMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  bool _isLoadingSessions = false;
  bool _isLexiThinking = false;
  bool _isLexiTyping = false;
  String? _error;
  bool _ttsEnabled = true;
  String _learnerLevel = 'B1';
  Timer? _typingStageTimer;

  // Audio player for Lexi's voice
  final AudioPlayer _ttsPlayer = AudioPlayer();

  // ── Getters ────────────────────────────────────────────────────────────────
  LexiSession? get session => _session;
  List<LexiSessionSummary> get sessions => List.unmodifiable(_sessions);
  List<LexiMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  bool get isLoadingSessions => _isLoadingSessions;
  bool get isLexiThinking => _isLexiThinking;
  bool get isLexiTyping => _isLexiTyping;
  bool get isLexiResponding => _isLexiThinking || _isLexiTyping;
  String? get error => _error;
  bool get hasSession => _session != null;
  bool get ttsEnabled => _ttsEnabled;
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

      // Add Lexi's greeting
      _messages.add(
        LexiMessage(
          id: 'greeting',
          role: 'assistant',
          content:
              "Squawk! 🦜 Hey there, adventurer! I'm Lexi, your English buddy. "
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
      _isLoading = false;
      logError(_tag, _error!);
      notifyListeners();
    }
  }

  Future<void> createNewSession(String userId) async {
    await startSession(userId);
  }

  Future<void> selectSession(LexiSessionSummary summary) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final remoteSessions = await repository.getSessions(
        userId: summary.userId,
      );
      final existsRemotely = remoteSessions.any(
        (s) => s.sessionId == summary.sessionId,
      );
      if (!existsRemotely) {
        _sessions.removeWhere((s) => s.sessionId == summary.sessionId);
        await _saveSessions();
        await startSession(summary.userId);
        _error = 'Session was expired on server. Started a new one.';
        return;
      }

      _session = LexiSession(
        sessionId: summary.sessionId,
        userId: summary.userId,
        createdAt: summary.createdAt,
        title: summary.title,
        updatedAt: summary.updatedAt,
      );

      final loaded = await repository.getMessages(sessionId: summary.sessionId);
      _messages
        ..clear()
        ..addAll(loaded);

      _touchSession(summary.sessionId);

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load session: $e';
      _isLoading = false;
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
    }
    await _saveSessions();
    notifyListeners();
  }

  // ── Send Message ───────────────────────────────────────────────────────────
  Future<void> sendMessage(String text, {String? userId}) async {
    if (text.trim().isEmpty || _isSending) return;

    final uid = userId ?? 'demo_user';
    final sessionId = _session?.sessionId ?? '';

    // Optimistic: add user message immediately
    final userMsg = LexiMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'user',
      content: text.trim(),
      timestamp: DateTime.now(),
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
      );

      _messages.add(response);
      _endLexiResponseState();
      _isSending = false;
      notifyListeners();

      // Auto-play TTS if available
      if (_ttsEnabled && response.hasAudio) {
        await _playTtsAudio(response.audioBase64!);
      }
    } catch (e) {
      _endLexiResponseState();
      _isSending = false;
      _error = 'Lexi couldn\'t respond: $e';
      logError(_tag, _error!);

      // Add error message from Lexi
      _messages.add(
        LexiMessage(
          id: 'error_${DateTime.now().millisecondsSinceEpoch}',
          role: 'assistant',
          content:
              "Squawk! 🦜 Oops, my feathers got tangled! "
              "Could you try again?",
          timestamp: DateTime.now(),
        ),
      );
      notifyListeners();
    }
  }

  // ── Voice Input ────────────────────────────────────────────────────────────
  Future<void> sendVoiceMessage(String audioBase64, {String? userId}) async {
    if (_isSending) return;

    final uid = userId ?? 'demo_user';
    final sessionId = _session?.sessionId ?? '';

    _isSending = true;
    _beginLexiResponseState();
    _error = null;

    // Show recording indicator
    _messages.add(
      LexiMessage(
        id: 'voice_${DateTime.now().millisecondsSinceEpoch}',
        role: 'user',
        content: '🎤 Voice message...',
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
      _endLexiResponseState();
      _isSending = false;
      notifyListeners();

      if (_ttsEnabled && response.hasAudio) {
        await _playTtsAudio(response.audioBase64!);
      }
    } catch (e) {
      _endLexiResponseState();
      _isSending = false;
      _error = 'Voice processing failed: $e';
      logError(_tag, _error!);
      notifyListeners();
    }
  }

  void _beginLexiResponseState() {
    _typingStageTimer?.cancel();
    _isLexiThinking = true;
    _isLexiTyping = false;

    // Transition to typing state if request takes longer.
    _typingStageTimer = Timer(const Duration(milliseconds: 700), () {
      if (!_isSending) return;
      _isLexiThinking = false;
      _isLexiTyping = true;
      notifyListeners();
    });
  }

  void _endLexiResponseState() {
    _typingStageTimer?.cancel();
    _isLexiThinking = false;
    _isLexiTyping = false;
  }

  // ── TTS Playback ──────────────────────────────────────────────────────────
  Future<void> _playTtsAudio(String base64Audio) async {
    try {
      final bytes = base64Decode(base64Audio);
      final uri = Uri.dataFromBytes(bytes, mimeType: 'audio/mpeg');
      await _ttsPlayer.setUrl(uri.toString());
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

  // ── Settings ──────────────────────────────────────────────────────────────
  void toggleTts() {
    _ttsEnabled = !_ttsEnabled;
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

  void _touchSession(String sessionId) {
    final idx = _sessions.indexWhere((s) => s.sessionId == sessionId);
    if (idx == -1) return;
    final item = _sessions.removeAt(idx).copyWith(updatedAt: DateTime.now());
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
}

class LexiSessionSummary {
  final String sessionId;
  final String userId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LexiSessionSummary({
    required this.sessionId,
    required this.userId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  LexiSessionSummary copyWith({String? title, DateTime? updatedAt}) {
    return LexiSessionSummary(
      sessionId: sessionId,
      userId: userId,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'user_id': userId,
      'title': title,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory LexiSessionSummary.fromJson(Map<String, dynamic> json) {
    return LexiSessionSummary(
      sessionId: json['session_id'] ?? '',
      userId: json['user_id'] ?? '',
      title: json['title'] ?? 'Lexi Chat',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
    );
  }
}
