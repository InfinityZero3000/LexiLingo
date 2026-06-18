import 'dart:typed_data';

import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/services/local_cache_service.dart';
import 'package:lexilingo_app/features/vocabulary/data/models/pronunciation_evaluation_model.dart';
import 'package:lexilingo_app/features/vocabulary/data/models/vocabulary_item_model.dart';
import 'package:lexilingo_app/features/vocabulary/data/models/user_vocabulary_model.dart';
import 'package:lexilingo_app/features/vocabulary/data/models/review_result_model.dart';

/// Vocabulary Remote Data Source (Data Layer)
/// Handles all vocabulary API calls
/// Clean Architecture: Data layer communicates with external APIs
abstract class VocabularyRemoteDataSource {
  /// Get vocabulary items (master list)
  Future<List<VocabularyItemModel>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? tag,
    String? search,
    int limit = 50,
    int offset = 0,
  });

  /// Get vocabulary item by ID
  Future<VocabularyItemModel> getVocabularyItem(String vocabularyId);

  /// Get user's vocabulary collection
  Future<List<UserVocabularyModel>> getUserCollection({
    String? status,
    int limit = 50,
    int offset = 0,
  });

  /// Add vocabulary to user's collection
  Future<UserVocabularyModel> addToCollection(String vocabularyId);

  /// Get due vocabulary for review
  Future<List<UserVocabularyModel>> getDueVocabulary({int limit = 20});

  /// Submit vocabulary review
  Future<ReviewResultModel> submitReview(
    String userVocabularyId,
    int quality, {
    int? timeSpentMs,
  });

  /// Evaluate a pronunciation recording for one vocabulary item
  Future<PronunciationEvaluationModel> evaluatePronunciation({
    required String vocabularyId,
    required Uint8List audioData,
    required String filename,
  });

  /// Get vocabulary statistics
  Future<Map<String, dynamic>> getVocabularyStats();

  /// Get vocabulary items in a deck
  Future<List<UserVocabularyModel>> getDeckItems(String deckId);

  /// Get today's Word of the Day
  Future<VocabularyItemModel> getWordOfDay();
}

/// Implementation of VocabularyRemoteDataSource
class VocabularyRemoteDataSourceImpl implements VocabularyRemoteDataSource {
  final ApiClient apiClient;

  VocabularyRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<List<VocabularyItemModel>> getVocabularyItems({
    String? courseId,
    String? lessonId,
    String? difficultyLevel,
    String? tag,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final pathParams = <String>[];
      pathParams.add('limit=$limit');
      pathParams.add('offset=$offset');
      if (courseId != null) pathParams.add('course_id=$courseId');
      if (lessonId != null) pathParams.add('lesson_id=$lessonId');
      if (difficultyLevel != null) {
        pathParams.add('difficulty_level=$difficultyLevel');
      }
      if (tag != null) pathParams.add('tag=$tag');
      if (search != null) pathParams.add('search=$search');

      final queryString = pathParams.isEmpty ? '' : '?${pathParams.join('&')}';
      final response = await apiClient.get('/vocabulary/items$queryString');

      final data = response['data'];
      if (data is! List<dynamic>) {
        throw ServerException('Invalid vocabulary items response');
      }

      return data.map((json) {
        if (json is! Map<String, dynamic>) {
          throw ServerException('Invalid vocabulary item response');
        }
        return VocabularyItemModel.fromJson(json);
      }).toList();
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to fetch vocabulary items: $e');
    }
  }

  @override
  Future<VocabularyItemModel> getVocabularyItem(String vocabularyId) async {
    try {
      final response = await apiClient.get('/vocabulary/items/$vocabularyId');
      return VocabularyItemModel.fromJson(response);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to fetch vocabulary item: $e');
    }
  }

  @override
  Future<List<UserVocabularyModel>> getUserCollection({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final pathParams = <String>[];
      pathParams.add('limit=$limit');
      pathParams.add('offset=$offset');
      if (status != null) pathParams.add('status=$status');

      final queryString = pathParams.isEmpty ? '' : '?${pathParams.join('&')}';
      final response = await apiClient.get(
        '/vocabulary/collection$queryString',
      );

      // Response format: {"items": [...], "total": 100, "has_more": true}
      final List<dynamic> items = response['items'] as List<dynamic>;

      return items.map((json) {
        return UserVocabularyModel.fromJson(json);
      }).toList();
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to fetch user collection: $e');
    }
  }

  @override
  Future<UserVocabularyModel> addToCollection(String vocabularyId) async {
    try {
      final response = await apiClient.post(
        '/vocabulary/collection?vocabulary_id=$vocabularyId',
      );

      return UserVocabularyModel.fromJson(response);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to add to collection: $e');
    }
  }

  @override
  Future<List<UserVocabularyModel>> getDueVocabulary({int limit = 20}) async {
    try {
      final cacheKey = 'due_vocab_$limit';
      final cached = await LocalCacheService.instance.getOrFetchList(
        key: cacheKey,
        type: 'flashcard',
        fetchFn: () async {
          final response = await apiClient.get('/vocabulary/due?limit=$limit');
          final List<dynamic> items = response['items'] as List<dynamic>;
          return items;
        },
      );
      return (cached ?? [])
          .map((json) => UserVocabularyModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to fetch due vocabulary: $e');
    }
  }

  @override
  Future<ReviewResultModel> submitReview(
    String userVocabularyId,
    int quality, {
    int? timeSpentMs,
  }) async {
    try {
      final body = ReviewSubmissionModel(
        quality: quality,
        timeSpentMs: timeSpentMs,
      ).toJson();

      final response = await apiClient.post(
        '/vocabulary/review/$userVocabularyId',
        body: body,
      );

      return ReviewResultModel.fromJson({...response, 'quality': quality});
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to submit review: $e');
    }
  }

  @override
  Future<PronunciationEvaluationModel> evaluatePronunciation({
    required String vocabularyId,
    required Uint8List audioData,
    required String filename,
  }) async {
    try {
      final response = await apiClient.postMultipart(
        '/vocabulary/pronunciation/evaluate',
        fields: {'vocabulary_id': vocabularyId},
        fileField: 'audio',
        fileBytes: audioData,
        filename: filename,
      );

      return PronunciationEvaluationModel.fromJson(response);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to evaluate pronunciation: $e');
    }
  }

  @override
  Future<Map<String, dynamic>> getVocabularyStats() async {
    try {
      final response = await apiClient.get('/vocabulary/stats');
      return response;
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to fetch vocabulary stats: $e');
    }
  }

  @override
  Future<List<UserVocabularyModel>> getDeckItems(String deckId) async {
    try {
      final response = await apiClient.get('/vocabulary/decks/$deckId/items');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => UserVocabularyModel.fromJson(json)).toList();
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to fetch deck items: $e');
    }
  }

  @override
  Future<VocabularyItemModel> getWordOfDay() async {
    try {
      final response = await apiClient.get('/vocabulary/word-of-day');
      final data = response['data'] ?? response;
      return VocabularyItemModel.fromJson(data as Map<String, dynamic>);
    } on ServerException {
      rethrow;
    } catch (e) {
      throw ServerException('Failed to fetch word of the day: $e');
    }
  }
}
