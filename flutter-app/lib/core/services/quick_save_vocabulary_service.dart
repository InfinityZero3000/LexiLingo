import 'dart:async';

import 'package:lexilingo_app/core/network/api_client.dart';

/// Result payload from quick-save vocabulary endpoint.
class QuickSaveVocabularyResult {
  final String normalizedWord;
  final bool createdNewItem;
  final bool alreadyInCollection;
  final String? vocabularyId;

  const QuickSaveVocabularyResult({
    required this.normalizedWord,
    required this.createdNewItem,
    required this.alreadyInCollection,
    required this.vocabularyId,
  });

  factory QuickSaveVocabularyResult.fromJson(Map<String, dynamic> json) {
    final vocabulary = json['vocabulary'] as Map<String, dynamic>?;
    return QuickSaveVocabularyResult(
      normalizedWord: json['normalized_word'] as String? ?? '',
      createdNewItem: json['created_new_item'] as bool? ?? false,
      alreadyInCollection: json['already_in_collection'] as bool? ?? false,
      vocabularyId: vocabulary?['id'] as String?,
    );
  }
}

/// Service used by multiple screens to quick-save selected words.
class QuickSaveVocabularyService {
  final ApiClient apiClient;
  final StreamController<QuickSaveVocabularyResult> _savedWordsController =
      StreamController<QuickSaveVocabularyResult>.broadcast();

  QuickSaveVocabularyService({required this.apiClient});

  Stream<QuickSaveVocabularyResult> get savedWords =>
      _savedWordsController.stream;

  Future<QuickSaveVocabularyResult> quickSaveWord({
    required String word,
    required String sourceType,
    String? sourceReference,
    String? contextSentence,
    String? definition,
    String? translation,
    String? partOfSpeech,
    String? difficultyLevel,
  }) async {
    final response = await apiClient.post(
      '/vocabulary/collection/quick-save',
      body: {
        'word': word,
        'source_type': sourceType,
        if (sourceReference != null && sourceReference.isNotEmpty)
          'source_reference': sourceReference,
        if (contextSentence != null && contextSentence.isNotEmpty)
          'context_sentence': contextSentence,
        if (definition != null && definition.isNotEmpty)
          'definition': definition,
        if (translation != null && translation.isNotEmpty)
          'translation': translation,
        if (partOfSpeech != null && partOfSpeech.isNotEmpty)
          'part_of_speech': partOfSpeech,
        if (difficultyLevel != null && difficultyLevel.isNotEmpty)
          'difficulty_level': difficultyLevel,
      },
    );

    final result = QuickSaveVocabularyResult.fromJson(response);
    _savedWordsController.add(result);
    return result;
  }

  void dispose() {
    _savedWordsController.close();
  }
}
