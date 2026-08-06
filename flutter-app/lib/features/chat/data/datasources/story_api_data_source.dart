import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import '../../../../core/utils/app_logger.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/network/sse_line_parser.dart';
import '../../domain/entities/topic_stream_event.dart';
import '../models/story_model.dart';
import '../models/topic_session_model.dart';

const _tag = 'StoryApiDataSource';

class TopicMessagesMetadataResult {
  final int totalCount;
  final bool hasMessages;
  final String? latestCursor;
  final String? oldestCursor;
  final String? latestTs;
  final String? oldestTs;

  const TopicMessagesMetadataResult({
    required this.totalCount,
    required this.hasMessages,
    required this.latestCursor,
    required this.oldestCursor,
    required this.latestTs,
    required this.oldestTs,
  });
}

/// Remote data source for Story/Topic-based conversation API
/// Connects to AI Service on port 8001
class StoryApiDataSource {
  final String baseUrl;
  final AiApiClient? _apiClient;

  StoryApiDataSource({
    AiApiClient? apiClient,
    String? baseUrl,
    http.Client? client,
    Future<Map<String, String>> Function()? authHeaderProvider,
  }) : baseUrl = baseUrl ?? ApiConfig.aiServiceUrl,
       _apiClient = apiClient;

  AiApiClient get apiClient => _apiClient ?? sl<AiApiClient>();

  /// Get all available stories
  Future<List<StoryListItem>> getStories({
    String? category,
    DifficultyLevel? difficultyLevel,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (category != null) queryParams['category'] = category;
      if (difficultyLevel != null) {
        queryParams['difficulty_level'] = difficultyLevel.shortName;
      }
      queryParams['limit'] = limit.toString();

      final uri = Uri(
        path: '/topics/stories',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );
      final pathWithQuery = uri.toString();

      logDebug(_tag, 'getStories: $pathWithQuery');

      final json = await apiClient.get(pathWithQuery);
      final storiesJson = json['stories'] as List<dynamic>? ?? [];

      if (storiesJson.isEmpty &&
          queryParams['category'] == null &&
          queryParams['difficulty_level'] == null) {
        final retryUri = Uri(
          path: '/topics/stories',
          queryParameters: {'limit': limit.toString(), 'bypass_cache': 'true'},
        );
        final retryPathWithQuery = retryUri.toString();

        logDebug(_tag, 'getStories retry with bypass_cache: $retryPathWithQuery');

        try {
          final retryJson = await apiClient.get(retryPathWithQuery);
          final retryStoriesJson = retryJson['stories'] as List<dynamic>? ?? [];
          return retryStoriesJson
              .map((e) => StoryListItem.fromJson(e as Map<String, dynamic>))
              .toList();
        } catch (retryErr) {
          logError(_tag, 'getStories retry failed: $retryErr');
        }
      }

      return storiesJson
          .map((e) => StoryListItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logError(_tag, 'getStories error: $e');
      rethrow;
    }
  }

  /// Get story details by ID
  Future<Story> getStoryDetails(String storyId) async {
    try {
      logDebug(_tag, 'getStoryDetails: $storyId');
      final json = await apiClient.get('/topics/stories/$storyId');
      return Story.fromJson(json);
    } catch (e) {
      logError(_tag, 'getStoryDetails error: $e');
      rethrow;
    }
  }

  /// Warm the cache for a specific topic
  Future<Map<String, dynamic>> warmTopicCache({
    required String storyId,
    required String userId,
  }) async {
    try {
      logDebug(_tag, 'warmTopicCache: $storyId');
      final body = {'story_id': storyId, 'user_id': userId};
      final json = await apiClient.post('/topics/stories/warm', body: body);
      return json;
    } catch (e) {
      logError(_tag, 'warmTopicCache error: $e');
      rethrow;
    }
  }

  /// Get available categories
  Future<List<String>> getCategories() async {
    try {
      logDebug(_tag, 'getCategories');
      final json = await apiClient.get('/topics/categories');
      final categories = json['categories'] as List<dynamic>? ?? [];
      return categories.cast<String>();
    } catch (e) {
      logError(_tag, 'getCategories error: $e');
      rethrow;
    }
  }

  /// Start a new topic session
  Future<TopicSession> startTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'tracecag',
  }) async {
    try {
      logDebug(_tag, 'startTopicSession storyId=$storyId');
      final body = {
        'user_id': userId,
        'story_id': storyId,
        if (sessionTitle != null) 'session_title': sessionTitle,
        'preferred_llm': preferredLlm,
      };

      final json = await apiClient.post('/topics/topic-sessions', body: body);
      return TopicSession.fromJson(json);
    } catch (e) {
      logError(_tag, 'startTopicSession error: $e');
      rethrow;
    }
  }

  /// Send message in a topic session
  Future<TopicChatResponse> sendTopicMessage({
    required String sessionId,
    required String userId,
    required String message,
  }) async {
    try {
      logDebug(_tag, 'sendTopicMessage sessionId=$sessionId');
      final body = {
        'session_id': sessionId,
        'user_id': userId,
        'message': message,
      };

      final json = await apiClient.post(
        '/topics/topic-sessions/$sessionId/messages',
        body: body,
      );
      return TopicChatResponse.fromJson(json);
    } catch (e) {
      logError(_tag, 'sendTopicMessage error: $e');
      rethrow;
    }
  }

  /// Send a message and receive an SSE stream of events, mirroring
  /// LexiChatDataSource.sendMessageStream. Yields:
  ///   1. [TopicStreamThinking] — pipeline started
  ///   2. [TopicStreamChunk]    — one word at a time (typewriter effect)
  ///   3. [TopicStreamDone]     — full response with hints/metadata
  ///   4. [TopicStreamError]    — on pipeline failure (may not follow thinking)
  Stream<TopicStreamEvent> sendTopicMessageStream({
    required String sessionId,
    required String userId,
    required String message,
  }) async* {
    logDebug(_tag, 'sendTopicMessageStream sessionId=$sessionId');
    final body = {
      'session_id': sessionId,
      'user_id': userId,
      'message': message,
    };

    final rawStream = apiClient.postStream(
      '/topics/topic-sessions/$sessionId/messages/stream',
      body: body,
    );

    await for (final sse in parseSseLines(rawStream)) {
      switch (sse.event) {
        case 'thinking':
          yield const TopicStreamThinking();
          break;
        case 'chunk':
          try {
            final json = jsonDecode(sse.data) as Map<String, dynamic>;
            final text = json['text'] as String? ?? '';
            if (text.isNotEmpty) yield TopicStreamChunk(text);
          } catch (_) {}
          break;
        case 'done':
          try {
            final json = jsonDecode(sse.data) as Map<String, dynamic>;
            yield TopicStreamDone(TopicChatResponse.fromJson(json).toEntity());
          } catch (e) {
            logError(_tag, 'sendTopicMessageStream: failed to parse done event: $e');
          }
          break;
        case 'error':
          try {
            final json = jsonDecode(sse.data) as Map<String, dynamic>;
            yield TopicStreamError(json['error'] as String? ?? 'Unknown error');
          } catch (_) {
            yield const TopicStreamError('Stream error');
          }
          break;
        default:
          break;
      }
    }
  }

  /// Get topic session details
  Future<TopicSession> getTopicSession(String sessionId) async {
    try {
      logDebug(_tag, 'getTopicSession sessionId=$sessionId');
      final json = await apiClient.get('/topics/topic-sessions/$sessionId');
      return TopicSession.fromJson(json);
    } catch (e) {
      logError(_tag, 'getTopicSession error: $e');
      rethrow;
    }
  }

  /// Get messages for a topic session
  Future<List<TopicChatMessage>> getTopicMessages(String sessionId) async {
    try {
      logDebug(_tag, 'getTopicMessages sessionId=$sessionId');
      final json = await apiClient.get(
        '/topics/topic-sessions/$sessionId/messages?limit=0',
      );
      final messagesJson = json['messages'] as List<dynamic>? ?? [];
      return messagesJson
          .map((e) => TopicChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      logError(_tag, 'getTopicMessages error: $e');
      rethrow;
    }
  }

  Future<TopicMessagesPageResult> getTopicMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) async {
    try {
      final safeLimit = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
      final query = StringBuffer('limit=$safeLimit');
      if (cursor != null && cursor.isNotEmpty) {
        query.write('&cursor=${Uri.encodeComponent(cursor)}');
      }

      final path = '/topics/topic-sessions/$sessionId/messages/paged?${query.toString()}';
      logDebug(_tag, 'getTopicMessagesPaged: $path');

      final json = await apiClient.get(path);
      final messagesJson = json['messages'] as List<dynamic>? ?? [];
      final pagination = Map<String, dynamic>.from(
        (json['pagination'] ?? const <String, dynamic>{}) as Map,
      );

      final messages = messagesJson
          .map((e) => TopicChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();

      return TopicMessagesPageResult(
        messages: messages,
        hasMore: pagination['has_more'] == true,
        nextCursor: pagination['next_cursor']?.toString(),
        returned: (pagination['returned'] as num?)?.toInt() ?? messages.length,
      );
    } catch (e) {
      logWarn(_tag, 'getTopicMessagesPaged fallback to full history: $e');
      final allMessages = await getTopicMessages(sessionId);
      return _fallbackTopicPage(
        allMessages: allMessages,
        limit: limit,
        cursor: cursor,
      );
    }
  }

  Future<TopicMessagesMetadataResult> getTopicMessagesMetadata(
    String sessionId,
  ) async {
    final path = '/topics/topic-sessions/$sessionId/messages/metadata';
    logDebug(_tag, 'getTopicMessagesMetadata: $path');

    final json = await apiClient.get(path);
    final metadata = Map<String, dynamic>.from(
      (json['metadata'] ?? const <String, dynamic>{}) as Map,
    );
    final totalCount = (metadata['total_count'] as num?)?.toInt() ?? 0;

    return TopicMessagesMetadataResult(
      totalCount: totalCount,
      hasMessages: metadata['has_messages'] == true,
      latestCursor: metadata['latest_cursor']?.toString(),
      oldestCursor: metadata['oldest_cursor']?.toString(),
      latestTs: metadata['latest_ts']?.toString(),
      oldestTs: metadata['oldest_ts']?.toString(),
    );
  }

  /// Check LLM health
  Future<Map<String, dynamic>> checkLlmHealth() async {
    try {
      logDebug(_tag, 'checkLlmHealth');
      final json = await apiClient.get('/topics/llm/health');
      return json;
    } catch (e) {
      logError(_tag, 'checkLlmHealth error: $e');
      rethrow;
    }
  }

  TopicMessagesPageResult _fallbackTopicPage({
    required List<TopicChatMessage> allMessages,
    required int limit,
    required String? cursor,
  }) {
    if (allMessages.isEmpty) {
      return const TopicMessagesPageResult(
        messages: [],
        hasMore: false,
        nextCursor: null,
        returned: 0,
      );
    }

    final safeLimit = limit < 1 ? 1 : (limit > 200 ? 200 : limit);
    int endIndex = allMessages.length;

    if (cursor != null && cursor.isNotEmpty) {
      final decoded = _decodeCursorBestEffort(cursor);
      final cursorId = decoded['id'];
      final cursorTs = decoded['timestamp'];
      final found = allMessages.indexWhere((m) {
        final idMatch = cursorId != null && m.id == cursorId;
        final tsMatch =
            cursorTs != null &&
            m.timestamp.toIso8601String().startsWith(cursorTs);
        return idMatch || tsMatch;
      });
      if (found >= 0) {
        endIndex = found;
      }
    }

    final startIndex = (endIndex - safeLimit) < 0 ? 0 : endIndex - safeLimit;
    final page = allMessages.sublist(startIndex, endIndex);
    final hasMore = startIndex > 0;

    return TopicMessagesPageResult(
      messages: page,
      hasMore: hasMore,
      nextCursor: hasMore && page.isNotEmpty ? _encodeCursor(page.first) : null,
      returned: page.length,
    );
  }

  String _encodeCursor(TopicChatMessage message) {
    final payload = '${message.timestamp.toIso8601String()}|${message.id}';
    return base64UrlEncode(utf8.encode(payload));
  }

  Map<String, String?> _decodeCursorBestEffort(String cursor) {
    try {
      final raw = utf8.decode(base64Url.decode(cursor));
      final parts = raw.split('|');
      if (parts.length < 2) return {'timestamp': null, 'id': null};
      return {'timestamp': parts[0], 'id': parts[1]};
    } catch (_) {
      return {'timestamp': null, 'id': null};
    }
  }
}
