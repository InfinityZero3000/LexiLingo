/// Vocabulary Item Entity (Domain Layer)
/// Represents a vocabulary word from the master database
/// Clean Architecture: Pure business model without dependencies
class VocabularyItemEntity {
  final String id;
  final String word;
  final String definition;
  final Map<String, dynamic>? translation; // {"vi": "...", "examples": [...]}
  final String? pronunciation; // IPA notation
  final String? audioUrl;
  final String partOfSpeech;
  final String difficultyLevel;
  final String? courseId;
  final String? lessonId;
  final List<String>? tags;
  final int usageFrequency;
  final DateTime createdAt;

  const VocabularyItemEntity({
    required this.id,
    required this.word,
    required this.definition,
    this.translation,
    this.pronunciation,
    this.audioUrl,
    required this.partOfSpeech,
    required this.difficultyLevel,
    this.courseId,
    this.lessonId,
    this.tags,
    this.usageFrequency = 0,
    required this.createdAt,
  });

  /// Get Vietnamese translation
  String? get vietnameseTranslation {
    return translation?['vi'] as String?;
  }

  /// Get example sentences
  List<String> get examples {
    final examplesList = translation?['examples'];
    if (examplesList is List) {
      return examplesList.cast<String>();
    }
    return [];
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VocabularyItemEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
