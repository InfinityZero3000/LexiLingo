import 'package:dartz/dartz.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/utils/app_logger.dart';
import '../../domain/repositories/story_repository.dart';
import '../datasources/story_api_data_source.dart';
import '../models/story_model.dart';
import '../models/topic_session_model.dart';

const _tag = 'StoryRepositoryImpl';

/// Implementation of StoryRepository
class StoryRepositoryImpl implements StoryRepository {
  final StoryApiDataSource apiDataSource;

  StoryRepositoryImpl({required this.apiDataSource});

  @override
  Future<Either<Failure, List<StoryListItem>>> getStories({
    String? category,
    DifficultyLevel? difficultyLevel,
    int limit = 20,
  }) async {
    try {
      final stories = await apiDataSource.getStories(
        category: category,
        difficultyLevel: difficultyLevel,
        limit: limit,
      );
      return Right(stories);
    } on ServerException catch (e) {
      logError(_tag, 'getStories server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'getStories error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Story>> getStoryDetails(String storyId) async {
    try {
      final story = await apiDataSource.getStoryDetails(storyId);
      return Right(story);
    } on ServerException catch (e) {
      logError(_tag, 'getStoryDetails server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'getStoryDetails error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<String>>> getCategories() async {
    try {
      final categories = await apiDataSource.getCategories();
      return Right(categories);
    } on ServerException catch (e) {
      logError(_tag, 'getCategories server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'getCategories error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TopicSession>> startTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'qwen',
  }) async {
    try {
      final session = await apiDataSource.startTopicSession(
        userId: userId,
        storyId: storyId,
        sessionTitle: sessionTitle,
        preferredLlm: preferredLlm,
      );
      return Right(session);
    } on ServerException catch (e) {
      logError(_tag, 'startTopicSession server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'startTopicSession error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TopicChatResponse>> sendTopicMessage({
    required String sessionId,
    required String userId,
    required String message,
  }) async {
    try {
      final response = await apiDataSource.sendTopicMessage(
        sessionId: sessionId,
        userId: userId,
        message: message,
      );
      return Right(response);
    } on ServerException catch (e) {
      logError(_tag, 'sendTopicMessage server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'sendTopicMessage error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, TopicSession>> getTopicSession(String sessionId) async {
    try {
      final session = await apiDataSource.getTopicSession(sessionId);
      return Right(session);
    } on ServerException catch (e) {
      logError(_tag, 'getTopicSession server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'getTopicSession error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<TopicChatMessage>>> getTopicMessages(
    String sessionId,
  ) async {
    try {
      final messages = await apiDataSource.getTopicMessages(sessionId);
      return Right(messages);
    } on ServerException catch (e) {
      logError(_tag, 'getTopicMessages server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'getTopicMessages error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> checkLlmHealth() async {
    try {
      final health = await apiDataSource.checkLlmHealth();
      return Right(health);
    } on ServerException catch (e) {
      logError(_tag, 'checkLlmHealth server error: $e');
      return Left(ServerFailure(e.message));
    } catch (e) {
      logError(_tag, 'checkLlmHealth error: $e');
      return Left(ServerFailure(e.toString()));
    }
  }
}
