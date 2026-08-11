/// Domain entities for AI educational hints (grammar/vocabulary feedback).
/// Pure Dart value objects — no JSON/serialization dependency.
library;

class GrammarCorrection {
  final String original;
  final String corrected;
  final String explanation;
  final String? errorType;
  final String? rule;

  const GrammarCorrection({
    required this.original,
    required this.corrected,
    required this.explanation,
    this.errorType,
    this.rule,
  });
}

class VocabularyHint {
  final String term;
  final String definition;
  final String? example;
  final String? partOfSpeech;
  final String? pronunciation;

  const VocabularyHint({
    required this.term,
    required this.definition,
    this.example,
    this.partOfSpeech,
    this.pronunciation,
  });
}

class EducationalHints {
  final List<GrammarCorrection> grammarCorrections;
  final List<VocabularyHint> vocabularyHints;
  final String? encouragement;
  final String? nextSuggestion;

  const EducationalHints({
    this.grammarCorrections = const [],
    this.vocabularyHints = const [],
    this.encouragement,
    this.nextSuggestion,
  });

  bool get hasGrammarHints => grammarCorrections.isNotEmpty;
  bool get hasVocabularyHints => vocabularyHints.isNotEmpty;
  bool get hasAnyHints => hasGrammarHints || hasVocabularyHints;
}

class LlmMetadata {
  final String provider;
  final String model;
  final int? latencyMs;
  final bool fallbackUsed;

  const LlmMetadata({
    required this.provider,
    required this.model,
    this.latencyMs,
    this.fallbackUsed = false,
  });
}
