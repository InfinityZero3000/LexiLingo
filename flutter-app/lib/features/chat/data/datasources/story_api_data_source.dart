import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/utils/app_logger.dart';
import '../../../../core/network/api_config.dart';
import '../../../../core/error/exceptions.dart';
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
  final http.Client _client;
  final Future<Map<String, String>> Function()? _authHeaderProvider;

  StoryApiDataSource({
    String? baseUrl,
    http.Client? client,
    Future<Map<String, String>> Function()? authHeaderProvider,
  }) : baseUrl = baseUrl ?? ApiConfig.aiServiceUrl,
       _client = client ?? http.Client(),
       _authHeaderProvider = authHeaderProvider;

  Future<Map<String, String>> _authHeaders() async {
    final base = {'Content-Type': 'application/json'};
    if (_authHeaderProvider == null) return base;
    final auth = await _authHeaderProvider();
    return {...base, ...auth};
  }

  /// Get all available stories
  Future<List<StoryListItem>> getStories({
    String? category,
    DifficultyLevel? difficultyLevel,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, String>{};
      if (category != null) queryParams['category'] = category;
      if (difficultyLevel != null) {
        queryParams['difficulty_level'] = difficultyLevel.shortName;
      }
      if (limit != 20) queryParams['limit'] = limit.toString();

      final uri = Uri.parse(
        '$baseUrl/topics/stories',
      ).replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      logDebug(_tag, 'getStories: $uri');

      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw ServerException('Failed to get stories: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final storiesJson = json['stories'] as List<dynamic>? ?? [];

      if (storiesJson.isEmpty &&
          queryParams['category'] == null &&
          queryParams['difficulty_level'] == null) {
        final retryUri = Uri.parse('$baseUrl/topics/stories').replace(
          queryParameters: {
            if (limit != 20) 'limit': limit.toString(),
            'bypass_cache': 'true',
          },
        );

        logDebug(_tag, 'getStories retry with bypass_cache: $retryUri');

        final retryResponse = await _client.get(
          retryUri,
          headers: {'Content-Type': 'application/json'},
        );

        if (retryResponse.statusCode == 200) {
          final retryJson =
              jsonDecode(retryResponse.body) as Map<String, dynamic>;
          final retryStoriesJson = retryJson['stories'] as List<dynamic>? ?? [];
          return retryStoriesJson
              .map((e) => StoryListItem.fromJson(e as Map<String, dynamic>))
              .toList();
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
      final uri = Uri.parse('$baseUrl/topics/stories/$storyId');
      logDebug(_tag, 'getStoryDetails: $uri');

      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw ServerException('Failed to get story: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
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
      final uri = Uri.parse('$baseUrl/topics/stories/warm');
      logDebug(_tag, 'warmTopicCache: $uri');

      final body = {'story_id': storyId, 'user_id': userId};

      final response = await _client.post(
        uri,
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw ServerException('Failed to warm cache: ${response.statusCode}');
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      logError(_tag, 'warmTopicCache error: $e');
      rethrow;
    }
  }

  /// Get available categories
  Future<List<String>> getCategories() async {
    try {
      final uri = Uri.parse('$baseUrl/topics/categories');
      logDebug(_tag, 'getCategories: $uri');

      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to get categories: ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
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
    String preferredLlm = 'graphcag',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/topics/topic-sessions');
      logDebug(_tag, 'startTopicSession: $uri');

      final body = {
        'user_id': userId,
        'story_id': storyId,
        if (sessionTitle != null) 'session_title': sessionTitle,
        'preferred_llm': preferredLlm,
      };

      final response = await _client.post(
        uri,
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to start session: ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
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
      final uri = Uri.parse(
        '$baseUrl/topics/topic-sessions/$sessionId/messages',
      );
      logDebug(_tag, 'sendTopicMessage: $uri');

      final body = {
        'session_id': sessionId,
        'user_id': userId,
        'message': message,
      };

      final response = await _client.post(
        uri,
        headers: await _authHeaders(),
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw ServerException('Failed to send message: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return TopicChatResponse.fromJson(json);
    } catch (e) {
      logError(_tag, 'sendTopicMessage error: $e');
      rethrow;
    }
  }

  /// Get topic session details
  Future<TopicSession> getTopicSession(String sessionId) async {
    try {
      final uri = Uri.parse('$baseUrl/topics/topic-sessions/$sessionId');
      logDebug(_tag, 'getTopicSession: $uri');

      final response = await _client.get(
        uri,
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        throw ServerException('Failed to get session: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return TopicSession.fromJson(json);
    } catch (e) {
      logError(_tag, 'getTopicSession error: $e');
      rethrow;
    }
  }

  /// Get messages for a topic session
  Future<List<TopicChatMessage>> getTopicMessages(String sessionId) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/topics/topic-sessions/$sessionId/messages?limit=0',
      );
      logDebug(_tag, 'getTopicMessages: $uri');

      final response = await _client.get(
        uri,
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        throw ServerException('Failed to get messages: ${response.statusCode}');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
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
      final query = <String, String>{
        'limit': limit < 1 ? '1' : (limit > 200 ? '200' : '$limit'),
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      };

      final uri = Uri.parse(
        '$baseUrl/topics/topic-sessions/$sessionId/messages/paged',
      ).replace(queryParameters: query);
      logDebug(_tag, 'getTopicMessagesPaged: $uri');

      final response = await _client.get(
        uri,
        headers: await _authHeaders(),
      );

      if (response.statusCode != 200) {
        throw ServerException(
          'Failed to get paged messages: ${response.statusCode}',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
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
    final uri = Uri.parse(
      '$baseUrl/topics/topic-sessions/$sessionId/messages/metadata',
    );
    logDebug(_tag, 'getTopicMessagesMetadata: $uri');

    final response = await _client.get(
      uri,
      headers: await _authHeaders(),
    );

    if (response.statusCode != 200) {
      throw ServerException(
        'Failed to get topic metadata: ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
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
      final uri = Uri.parse('$baseUrl/topics/llm/health');
      logDebug(_tag, 'checkLlmHealth: $uri');

      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw ServerException(
          'LLM health check failed: ${response.statusCode}',
        );
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
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
