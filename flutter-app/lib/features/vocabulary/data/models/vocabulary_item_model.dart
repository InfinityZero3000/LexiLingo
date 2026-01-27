import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';

/// Vocabulary Item Model (Data Layer)
/// Converts between API JSON and Domain Entity
class VocabularyItemModel extends VocabularyItemEntity {
  const VocabularyItemModel({
    required super.id,
    required super.word,
    required super.definition,
    super.translation,
    super.pronunciation,
    super.audioUrl,
    required super.partOfSpeech,
    required super.difficultyLevel,
    super.courseId,
    super.lessonId,
    super.tags,
    super.usageFrequency,
    required super.createdAt,
  });

  /// Create from JSON (API response)
  factory VocabularyItemModel.fromJson(Map<String, dynamic> json) {
    return VocabularyItemModel(
      id: json['id'] as String,
      word: json['word'] as String,
      definition: json['definition'] as String,
      translation: json['translation'] as Map<String, dynamic>?,
      pronunciation: json['pronunciation'] as String?,
      audioUrl: json['audio_url'] as String?,
      partOfSpeech: json['part_of_speech'] as String,
      difficultyLevel: json['difficulty_level'] as String,
      courseId: json['course_id'] as String?,
      lessonId: json['lesson_id'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>(),
      usageFrequency: (json['usage_frequency'] as int?) ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Convert to JSON (API request)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'word': word,
      'definition': definition,
      'translation': translation,
      'pronunciation': pronunciation,
      'audio_url': audioUrl,
      'part_of_speech': partOfSpeech,
      'difficulty_level': difficultyLevel,
      'course_id': courseId,
      'lesson_id': lessonId,
      'tags': tags,
      'usage_frequency': usageFrequency,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// Convert to Entity
  VocabularyItemEntity toEntity() {
    return VocabularyItemEntity(
      id: id,
      word: word,
      definition: definition,
      translation: translation,
      pronunciation: pronunciation,
      audioUrl: audioUrl,
      partOfSpeech: partOfSpeech,
      difficultyLevel: difficultyLevel,
      courseId: courseId,
      lessonId: lessonId,
      tags: tags,
      usageFrequency: usageFrequency,
      createdAt: createdAt,
    );
  }
}
