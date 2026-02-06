/// Educational Hints model for Topic-Based Conversation
/// Provides grammar corrections and vocabulary hints from AI responses

/// Grammar correction from AI
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

  factory GrammarCorrection.fromJson(Map<String, dynamic> json) {
    return GrammarCorrection(
      original: json['original'] as String? ?? '',
      corrected: json['corrected'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      errorType: json['error_type'] as String? ?? json['errorType'] as String?,
      rule: json['rule'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'original': original,
    'corrected': corrected,
    'explanation': explanation,
    'error_type': errorType,
    'rule': rule,
  };
}

/// Vocabulary hint from AI
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

  factory VocabularyHint.fromJson(Map<String, dynamic> json) {
    return VocabularyHint(
      term: json['term'] as String? ?? json['word'] as String? ?? '',
      definition: json['definition'] as String? ?? json['meaning'] as String? ?? '',
      example: json['example'] as String?,
      partOfSpeech: json['part_of_speech'] as String? ?? json['partOfSpeech'] as String?,
      pronunciation: json['pronunciation'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'term': term,
    'definition': definition,
    'example': example,
    'part_of_speech': partOfSpeech,
    'pronunciation': pronunciation,
  };
}

/// Educational hints container
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

  factory EducationalHints.fromJson(Map<String, dynamic> json) {
    return EducationalHints(
      grammarCorrections: (json['grammar_corrections'] as List<dynamic>?)
              ?.map((e) => GrammarCorrection.fromJson(e as Map<String, dynamic>))
              .toList() ??
          (json['grammarCorrections'] as List<dynamic>?)
              ?.map((e) => GrammarCorrection.fromJson(e as Map<String, dynamic>))
              .toList() ?? [],
      vocabularyHints: (json['vocabulary_hints'] as List<dynamic>?)
              ?.map((e) => VocabularyHint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          (json['vocabularyHints'] as List<dynamic>?)
              ?.map((e) => VocabularyHint.fromJson(e as Map<String, dynamic>))
              .toList() ?? [],
      encouragement: json['encouragement'] as String?,
      nextSuggestion: json['next_suggestion'] as String? ?? json['nextSuggestion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'grammar_corrections': grammarCorrections.map((g) => g.toJson()).toList(),
    'vocabulary_hints': vocabularyHints.map((v) => v.toJson()).toList(),
    'encouragement': encouragement,
    'next_suggestion': nextSuggestion,
  };

  bool get hasGrammarHints => grammarCorrections.isNotEmpty;
  bool get hasVocabularyHints => vocabularyHints.isNotEmpty;
  bool get hasAnyHints => hasGrammarHints || hasVocabularyHints;
}

/// LLM metadata from AI response
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

  factory LlmMetadata.fromJson(Map<String, dynamic> json) {
    return LlmMetadata(
      provider: json['provider'] as String? ?? '',
      model: json['model'] as String? ?? '',
      latencyMs: json['latency_ms'] as int? ?? json['latencyMs'] as int?,
      fallbackUsed: json['fallback_used'] as bool? ?? json['fallbackUsed'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'model': model,
    'latency_ms': latencyMs,
    'fallback_used': fallbackUsed,
  };
}
