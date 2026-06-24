/// Topic Session model for Topic-Based Conversation
/// Manages topic-based chat sessions with story context
library;

import 'story_model.dart';
import 'educational_hints_model.dart';
import '../../domain/entities/topic_session.dart' as entities;

/// Request to start a topic session
class StartTopicSessionRequest {
  final String userId;
  final String storyId;
  final String? sessionTitle;
  final String preferredLlm;

  const StartTopicSessionRequest({
    required this.userId,
    required this.storyId,
    this.sessionTitle,
    this.preferredLlm = 'tracecag',
  });

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'story_id': storyId,
    'session_title': sessionTitle,
    'preferred_llm': preferredLlm,
  };
}

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

  factory TopicSession.fromJson(Map<String, dynamic> json) {
    return TopicSession(
      sessionId:
          json['session_id'] as String? ?? json['sessionId'] as String? ?? '',
      story: StoryListItem.fromJson(json['story'] as Map<String, dynamic>),
      rolePersona: RolePersona.fromJson(
        json['role_persona'] as Map<String, dynamic>? ??
            json['rolePersona'] as Map<String, dynamic>? ??
            {},
      ),
      openingMessage:
          json['opening_message'] as String? ??
          json['openingMessage'] as String? ??
          '',
      vocabularyPreview:
          (json['vocabulary_preview'] as List<dynamic>?)
              ?.map((e) => VocabularyItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          (json['vocabularyPreview'] as List<dynamic>?)
              ?.map((e) => VocabularyItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'story': story.toJson(),
    'role_persona': rolePersona.toJson(),
    'opening_message': openingMessage,
    'vocabulary_preview': vocabularyPreview.map((v) => v.toJson()).toList(),
    'created_at': createdAt.toIso8601String(),
  };
}

/// Request to send a message in a topic session
class TopicChatRequest {
  final String sessionId;
  final String userId;
  final String message;

  const TopicChatRequest({
    required this.sessionId,
    required this.userId,
    required this.message,
  });

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'user_id': userId,
    'message': message,
  };
}

/// Response from AI in a topic session
class TopicChatResponse {
  final String response;
  final String? _messageId;
  final EducationalHints? educationalHints;
  final int? processingTimeMs;
  final LlmMetadata? llmMetadata;

  const TopicChatResponse({
    required this.response,
    String? messageId,
    this.educationalHints,
    this.processingTimeMs,
    this.llmMetadata,
  }) : _messageId = messageId;

  factory TopicChatResponse.fromJson(Map<String, dynamic> json) {
    final clean = (json['clean_response'] as String?)?.trim();
    final raw =
        (json['ai_response'] as String? ?? json['response'] as String? ?? '')
            .trim();

    return TopicChatResponse(
      response: (clean != null && clean.isNotEmpty) ? clean : raw,
      messageId: json['message_id'] as String? ?? json['messageId'] as String?,
      educationalHints: json['educational_hints'] != null
          ? EducationalHints.fromJson(
              json['educational_hints'] as Map<String, dynamic>,
            )
          : json['educationalHints'] != null
          ? EducationalHints.fromJson(
              json['educationalHints'] as Map<String, dynamic>,
            )
          : null,
      processingTimeMs:
          json['processing_time_ms'] as int? ??
          json['processingTimeMs'] as int?,
      llmMetadata: json['llm_metadata'] != null
          ? LlmMetadata.fromJson(json['llm_metadata'] as Map<String, dynamic>)
          : json['llmMetadata'] != null
          ? LlmMetadata.fromJson(json['llmMetadata'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'response': response,
    'educational_hints': educationalHints?.toJson(),
    'processing_time_ms': processingTimeMs,
    'llm_metadata': llmMetadata?.toJson(),
  };

  String get displayResponse => response;
  bool get hasHints => educationalHints?.hasAnyHints ?? false;

  // Additional getters for compatibility
  String get messageId =>
      _messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
  String get aiResponse => response;
  String get cleanResponse => response;
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

  factory TopicChatMessage.fromJson(Map<String, dynamic> json) {
    final roleRaw = (json['role'] ?? '').toString().toLowerCase();
    final bool computedIsUser =
        json['is_user'] as bool? ??
        json['isUser'] as bool? ??
        roleRaw == 'user';

    return TopicChatMessage(
      id: json['id'] as String? ?? json['message_id'] as String? ?? '',
      sessionId:
          json['session_id'] as String? ?? json['sessionId'] as String? ?? '',
      content: json['content'] as String? ?? json['message'] as String? ?? '',
      isUser: computedIsUser,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
      hints: json['hints'] != null
          ? EducationalHints.fromJson(json['hints'] as Map<String, dynamic>)
          : json['educational_hints'] != null
          ? EducationalHints.fromJson(
              json['educational_hints'] as Map<String, dynamic>,
            )
          : null,
      llmMetadata: json['llm_metadata'] != null
          ? LlmMetadata.fromJson(json['llm_metadata'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'session_id': sessionId,
    'content': content,
    'is_user': isUser,
    'timestamp': timestamp.toIso8601String(),
    'hints': hints?.toJson(),
    'llm_metadata': llmMetadata?.toJson(),
  };

  String get displayContent {
    // Strip <think>...</think> blocks (including multiline) from AI responses
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

/// Response from stories list API
class StoriesListResponse {
  final List<StoryListItem> stories;
  final int total;
  final int page;
  final int limit;

  const StoriesListResponse({
    required this.stories,
    required this.total,
    this.page = 1,
    this.limit = 100,
  });

  factory StoriesListResponse.fromJson(Map<String, dynamic> json) {
    return StoriesListResponse(
      stories:
          (json['stories'] as List<dynamic>?)
              ?.map((e) => StoryListItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          (json['items'] as List<dynamic>?)
              ?.map((e) => StoryListItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 100,
    );
  }

  Map<String, dynamic> toJson() => {
    'stories': stories.map((s) => s.toJson()).toList(),
    'total': total,
    'page': page,
    'limit': limit,
  };
}

// ---------------------------------------------------------------------------
// Domain entity mappers — see story_model.dart for rationale.
// ---------------------------------------------------------------------------

extension TopicSessionToEntity on TopicSession {
  entities.TopicSession toEntity() => entities.TopicSession(
    sessionId: sessionId,
    story: story.toEntity(),
    rolePersona: rolePersona.toEntity(),
    openingMessage: openingMessage,
    vocabularyPreview: vocabularyPreview.map((v) => v.toEntity()).toList(),
    createdAt: createdAt,
  );
}

extension TopicChatResponseToEntity on TopicChatResponse {
  entities.TopicChatResponse toEntity() => entities.TopicChatResponse(
    response: response,
    messageIdOverride: messageId,
    educationalHints: educationalHints?.toEntity(),
    processingTimeMs: processingTimeMs,
    llmMetadata: llmMetadata?.toEntity(),
  );
}

extension TopicChatMessageToEntity on TopicChatMessage {
  entities.TopicChatMessage toEntity() => entities.TopicChatMessage(
    id: id,
    sessionId: sessionId,
    content: content,
    isUser: isUser,
    timestamp: timestamp,
    hints: hints?.toEntity(),
    llmMetadata: llmMetadata?.toEntity(),
  );
}

extension TopicMessagesPageResultToEntity on TopicMessagesPageResult {
  entities.TopicMessagesPageResult toEntity() =>
      entities.TopicMessagesPageResult(
        messages: messages.map((m) => m.toEntity()).toList(),
        hasMore: hasMore,
        nextCursor: nextCursor,
        returned: returned,
      );
}
