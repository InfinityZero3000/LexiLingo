import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../../../core/utils/app_logger.dart';
import '../../../../core/utils/constants.dart';
import '../../../../core/error/exceptions.dart';
import '../models/story_model.dart';
import '../models/topic_session_model.dart';

const _tag = 'StoryApiDataSource';

/// Remote data source for Story/Topic-based conversation API
/// Connects to AI Service on port 8001
class StoryApiDataSource {
  final String baseUrl;
  final http.Client _client;

  StoryApiDataSource({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? AppConstants.aiServiceUrl,
        _client = client ?? http.Client();

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

      final uri = Uri.parse('$baseUrl/topics/stories').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

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
        throw ServerException('Failed to get categories: ${response.statusCode}');
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
    String preferredLlm = 'qwen',
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
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw ServerException('Failed to start session: ${response.statusCode}');
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
      final uri = Uri.parse('$baseUrl/topics/topic-sessions/$sessionId/messages');
      logDebug(_tag, 'sendTopicMessage: $uri');

      final body = {
        'session_id': sessionId,
        'user_id': userId,
        'message': message,
      };

      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
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
        headers: {'Content-Type': 'application/json'},
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
      final uri = Uri.parse('$baseUrl/topics/topic-sessions/$sessionId/messages');
      logDebug(_tag, 'getTopicMessages: $uri');

      final response = await _client.get(
        uri,
        headers: {'Content-Type': 'application/json'},
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
        throw ServerException('LLM health check failed: ${response.statusCode}');
      }

      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      logError(_tag, 'checkLlmHealth error: $e');
      rethrow;
    }
  }

}
