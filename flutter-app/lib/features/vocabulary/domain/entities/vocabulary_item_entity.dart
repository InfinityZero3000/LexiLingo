import 'word_translation.dart';

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

  /// Get localized translation dynamically.
  /// Never falls back to Vietnamese — showing `vi` to a non-Vietnamese user is
  /// noise, not a translation. Null means "no translation for this locale".
  /// A copy of the English definition is not a translation either, so it is
  /// hidden rather than shown twice.
  String? getTranslation(String localeCode) =>
      localizedGloss(translation, definition, localeCode);

  /// The English definition in the user's language
  /// (`translation.definitions.<locale>`). Null when absent — no fallback —
  /// or when it only repeats the English text (a cognate of a one-word
  /// definition such as "opposition").
  String? getDefinitionTranslation(String localeCode) =>
      localizedDefinition(translation, definition, localeCode);

  /// Get Vietnamese translation
  String? get vietnameseTranslation {
    return translation?['vi'] as String?;
  }

  /// Get example sentences
  List<String> get examples => translationExamples(translation);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VocabularyItemEntity && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
