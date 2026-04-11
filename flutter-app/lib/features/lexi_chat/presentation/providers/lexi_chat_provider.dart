import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  LexiChatProvider({required this.repository});

  // ── State ──────────────────────────────────────────────────────────────────
  LexiSession? _session;
  final List<LexiMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
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
  List<LexiMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
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
      notifyListeners();
    } catch (e) {
      _error = 'Failed to start session: $e';
      _isLoading = false;
      logError(_tag, _error!);
      notifyListeners();
    }
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
}
