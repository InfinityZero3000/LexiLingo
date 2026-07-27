/// Domain entities for Topic-Based Conversation sessions.
/// Pure Dart value objects — no JSON/serialization dependency, no data-layer imports.
library;

import 'story.dart';
import 'educational_hints.dart';

/// Response after starting a topic session
class TopicSession {
  final String sessionId;
  final StoryListItem story;
  final RolePersona rolePersona;
  final String openingMessage;
  final List<VocabularyItem> vocabularyPreview;
  final DateTime createdAt;

  const TopicSession({
    required this.sessionId,
    required this.story,
    required this.rolePersona,
    required this.openingMessage,
    this.vocabularyPreview = const [],
    required this.createdAt,
  });

  /// Local persistence only (the provider's "resume an active session"
  /// cache) — not an API contract, so it lives on the entity itself rather
  /// than pulling in the data-layer model.
  Map<String, dynamic> toCacheJson() => {
    'session_id': sessionId,
    'story': story.toCacheJson(),
    'role_persona': {
      'name': rolePersona.name,
      'role': rolePersona.role,
      'personality': rolePersona.personality,
      'speaking_style': rolePersona.speakingStyle,
      'background': rolePersona.background,
    },
    'opening_message': openingMessage,
    'created_at': createdAt.toIso8601String(),
  };

  factory TopicSession.fromCacheJson(Map<String, dynamic> json) {
    final personaJson = json['role_persona'] as Map<String, dynamic>? ?? {};
    return TopicSession(
      sessionId: json['session_id'] as String? ?? '',
      story: StoryListItem.fromCacheJson(
        json['story'] as Map<String, dynamic>,
      ),
      rolePersona: RolePersona(
        name: personaJson['name'] as String? ?? '',
        role: personaJson['role'] as String? ?? '',
        personality: personaJson['personality'] as String? ?? '',
        speakingStyle: personaJson['speaking_style'] as String? ?? '',
        background: personaJson['background'] as String? ?? '',
      ),
      openingMessage: json['opening_message'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Response from AI in a topic session
class TopicChatResponse {
  final String response;
  final String? messageIdOverride;
  final EducationalHints? educationalHints;
  final int? processingTimeMs;
  final LlmMetadata? llmMetadata;

  const TopicChatResponse({
    required this.response,
    this.messageIdOverride,
    this.educationalHints,
    this.processingTimeMs,
    this.llmMetadata,
  });

  String get messageId =>
      messageIdOverride ?? DateTime.now().millisecondsSinceEpoch.toString();
  bool get hasHints => educationalHints?.hasAnyHints ?? false;
}

/// A message in the topic chat
class TopicChatMessage {
  final String id;
  final String sessionId;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final EducationalHints? hints;
  final LlmMetadata? llmMetadata;

  const TopicChatMessage({
    required this.id,
    required this.sessionId,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.hints,
    this.llmMetadata,
  });

  String get displayContent {
    return content
        .replaceAll(
          RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
          '',
        )
        .trim();
  }

  bool get hasHints => hints?.hasAnyHints ?? false;
}

/// Cursor-based page result for topic chat messages.
class TopicMessagesPageResult {
  final List<TopicChatMessage> messages;
  final bool hasMore;
  final String? nextCursor;
  final int returned;

  const TopicMessagesPageResult({
    required this.messages,
    required this.hasMore,
    required this.nextCursor,
    required this.returned,
  });
}
