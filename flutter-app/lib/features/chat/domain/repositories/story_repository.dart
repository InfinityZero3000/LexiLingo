import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../../data/models/story_model.dart';
import '../../data/models/topic_session_model.dart';

/// Repository interface for Story/Topic-based conversation
abstract class StoryRepository {
  /// Get all available stories
  Future<Either<Failure, List<StoryListItem>>> getStories({
    String? category,
    DifficultyLevel? difficultyLevel,
    int limit = 20,
  });

  /// Get full story details
  Future<Either<Failure, Story>> getStoryDetails(String storyId);

  /// Get available categories
  Future<Either<Failure, List<String>>> getCategories();

  /// Start a topic-based chat session
  Future<Either<Failure, TopicSession>> startTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'qwen',
  });

  /// Send a message in a topic session
  Future<Either<Failure, TopicChatResponse>> sendTopicMessage({
    required String sessionId,
    required String userId,
    required String message,
  });

  /// Get topic session details
  Future<Either<Failure, TopicSession>> getTopicSession(String sessionId);

  /// Get messages for a topic session
  Future<Either<Failure, List<TopicChatMessage>>> getTopicMessages(String sessionId);

  /// Check LLM health status
  Future<Either<Failure, Map<String, dynamic>>> checkLlmHealth();
}
