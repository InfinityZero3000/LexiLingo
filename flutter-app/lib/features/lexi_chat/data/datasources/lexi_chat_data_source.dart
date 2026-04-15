import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';

const _tag = 'LexiChatDataSource';

/// Remote data source for Lexi Chat — talks to AI Service at :8001.
class LexiChatDataSource {
  final ApiClient apiClient;

  LexiChatDataSource({required this.apiClient});

  String _sanitizeAssistantContent(String input) {
    var text = input;

    // Remove hidden reasoning blocks if the model leaks them.
    text = text.replaceAll(
      RegExp(r'<think\b[^>]*>[\s\S]*?<\/think>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(RegExp(r'<\/?think>', caseSensitive: false), '');

    // Remove leaked internal GraphCAG payloads from assistant content.
    text = text.replaceAll(
      RegExp(
        r'\[JIT_SOFT_GRAPH\]\s*(?:\n|\r\n?)?\s*\{[\s\S]*?\}\s*',
        caseSensitive: false,
      ),
      '',
    );
    text = text.replaceAll(
      RegExp(
        r'^\s*\{(?:\\?"v\\?"|"v")[\s\S]*?(?:\\?"e\\?"|"e")[\s\S]*?\}\s*$',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );

    // Remove markdown wrappers that should not appear in plain chat bubbles.
    text = text.replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => m[1] ?? '');
    text = text.replaceAllMapped(RegExp(r'__(.*?)__'), (m) => m[1] ?? '');
    text = text.replaceAll('`', '');

    // Normalize excessive blank lines from stripped sections.
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    if (text.isEmpty) {
      return 'Squawk! I had a small glitch. Can you ask that again?';
    }

    return text;
  }

  /// Create a new Lexi session.
  Future<LexiSession> createSession({required String userId}) async {
    try {
      final json = await apiClient.post(
        '/lexi/sessions',
        body: {'user_id': userId},
      );
      logDebug(_tag, 'createSession: $json');

      final data = json['data'] ?? json;
      return LexiSession(
        sessionId: data['session_id'] ?? '',
        userId: userId,
        createdAt:
            DateTime.tryParse(data['created_at'] ?? '') ?? DateTime.now(),
      );
    } catch (e) {
      logError(_tag, 'createSession failed: $e');
      // Return a local session ID as fallback
      return LexiSession(
        sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
        userId: userId,
        createdAt: DateTime.now(),
      );
    }
  }

  /// Send a message to Lexi and get a structured response.
  Future<LexiMessage> sendMessage({
    required String userId,
    required String sessionId,
    required String message,
    String inputType = 'text',
    String? audioBase64,
    bool enableTts = true,
    String learnerLevel = 'B1',
    String? storyContext,
  }) async {
    final payload = {
      'user_id': userId,
      'session_id': sessionId,
      'message': message,
      'input_type': inputType,
      if (audioBase64 != null) 'audio_base64': audioBase64,
      'enable_tts': enableTts,
      'learner_level': learnerLevel,
      if (storyContext != null) 'story_context': storyContext,
    };

    final json = await apiClient.post(
      '/lexi/chat',
      body: payload,
      timeout: AppConstants.aiOperationTimeout,
    );

    final data = json['data'] ?? json;
    logDebug(_tag, 'sendMessage response keys: ${data.keys}');

    // Parse corrections
    final corrections = <LexiCorrection>[];
    final rawCorrections = data['corrections'] as List?;
    if (rawCorrections != null) {
      for (final c in rawCorrections) {
        corrections.add(
          LexiCorrection(
            errorSpan: c['error_span'] ?? '',
            correction: c['correction'] ?? '',
            errorType: c['error_type'] ?? '',
            explanation: c['explanation'] ?? '',
          ),
        );
      }
    }

    // Parse linked concepts
    final linkedConcepts = <String>[];
    final rawConcepts = data['linked_concepts'] as List?;
    if (rawConcepts != null) {
      linkedConcepts.addAll(rawConcepts.cast<String>());
    }

    // Parse scores
    Map<String, dynamic>? scores;
    if (data['scores'] != null) {
      scores = Map<String, dynamic>.from(data['scores']);
    }

    return LexiMessage(
      id:
          data['message_id'] ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      role: 'assistant',
      content: _sanitizeAssistantContent(
        data['lexi_response'] ??
            data['response'] ??
            'Squawk! Something went wrong.',
      ),
      timestamp: DateTime.now(),
      audioBase64: data['audio_base64'],
      corrections: corrections,
      linkedConcepts: linkedConcepts,
      vietnameseHint: data['vietnamese_hint'],
      scores: scores,
    );
  }

  /// Get messages for a Lexi session.
  Future<List<LexiMessage>> getMessages({required String sessionId}) async {
    if (sessionId.isEmpty) return [];

    try {
      final json = await apiClient.get('/lexi/sessions/$sessionId/messages');
      final data = json['data'] ?? json;
      final rawMessages = data['messages'] as List? ?? [];

      return rawMessages.map((m) {
        final role = m['role'] ?? 'user';
        final rawContent = m['content'] ?? '';
        return LexiMessage(
          id: m['id'] ?? '',
          role: role,
          content: role == 'assistant'
              ? _sanitizeAssistantContent(rawContent)
              : rawContent,
          timestamp: DateTime.tryParse(m['timestamp'] ?? '') ?? DateTime.now(),
        );
      }).toList();
    } catch (e) {
      logWarn(_tag, 'getMessages failed: $e');
      rethrow;
    }
  }

  Future<List<LexiSession>> getSessions({required String userId}) async {
    try {
      final json = await apiClient.get('/lexi/sessions/user/$userId');
      final data = json['data'] ?? json;
      final rawSessions = data['sessions'] as List? ?? [];

      return rawSessions.map((s) {
        return LexiSession(
          sessionId: s['session_id'] ?? '',
          userId: s['user_id'] ?? userId,
          createdAt: DateTime.tryParse(s['created_at'] ?? '') ?? DateTime.now(),
          title: s['title']?.toString(),
          updatedAt: DateTime.tryParse(s['updated_at'] ?? ''),
          messageCount: (s['message_count'] as num?)?.toInt(),
        );
      }).toList();
    } catch (e) {
      logWarn(_tag, 'getSessions failed: $e');
      return [];
    }
  }

  Future<void> renameSession({
    required String sessionId,
    required String title,
  }) async {
    await apiClient.post(
      '/lexi/sessions/$sessionId/rename',
      body: {'title': title},
    );
  }

  Future<void> deleteSession({required String sessionId}) async {
    await apiClient.post('/lexi/sessions/$sessionId/delete', body: {});
  }
}
