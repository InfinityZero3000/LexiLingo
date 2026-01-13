import 'package:equatable/equatable.dart';

/// Result of AI analysis on a user message
/// Contains grammar corrections, fluency score, vocabulary level, etc.
class AIAnalysisResult extends Equatable {
  /// ID of the message that was analyzed
  final String messageId;

  /// Fluency score and analysis
  final FluencyScore? fluency;

  /// Vocabulary level analysis
  final VocabularyLevel? vocabularyLevel;

  /// List of grammar errors found
  final List<GrammarError> grammarErrors;

  /// Corrected version of the text (if there were errors)
  final String? correctedText;

  /// When this analysis was performed
  final DateTime analyzedAt;

  const AIAnalysisResult({
    required this.messageId,
    this.fluency,
    this.vocabularyLevel,
    required this.grammarErrors,
    this.correctedText,
    required this.analyzedAt,
  });

  /// Check if there are any grammar errors
  bool get hasGrammarErrors => grammarErrors.isNotEmpty;

  /// Check if the text needed correction
  bool get needsCorrection => correctedText != null && correctedText!.isNotEmpty;

  /// Get a summary of issues found
  String get issueSummary {
    final issues = <String>[];
    if (hasGrammarErrors) issues.add('${grammarErrors.length} grammar errors');
    if (fluency != null && fluency!.score < 0.7) issues.add('low fluency');
    if (vocabularyLevel != null) issues.add('${vocabularyLevel!.level} level');
    return issues.isEmpty ? 'No issues' : issues.join(', ');
  }

  AIAnalysisResult copyWith({
    String? messageId,
    FluencyScore? fluency,
    VocabularyLevel? vocabularyLevel,
    List<GrammarError>? grammarErrors,
    String? correctedText,
    DateTime? analyzedAt,
  }) {
    return AIAnalysisResult(
      messageId: messageId ?? this.messageId,
      fluency: fluency ?? this.fluency,
      vocabularyLevel: vocabularyLevel ?? this.vocabularyLevel,
      grammarErrors: grammarErrors ?? this.grammarErrors,
      correctedText: correctedText ?? this.correctedText,
      analyzedAt: analyzedAt ?? this.analyzedAt,
    );
  }

  @override
  List<Object?> get props => [
        messageId,
        fluency,
        vocabularyLevel,
        grammarErrors,
        correctedText,
        analyzedAt,
      ];
}

/// Represents fluency score and analysis
class FluencyScore extends Equatable {
  /// Score from 0.0 to 1.0 (0 = not fluent, 1 = very fluent)
  final double score;

  /// CEFR level (A2, B1, B2)
  final String level;

  /// List of fluency issues detected
  final List<String> issues;

  const FluencyScore({
    required this.score,
    required this.level,
    required this.issues,
  });

  /// Get a human-readable description
  String get description {
    if (score >= 0.9) return 'Excellent';
    if (score >= 0.8) return 'Very Good';
    if (score >= 0.7) return 'Good';
    if (score >= 0.6) return 'Fair';
    return 'Needs Improvement';
  }

  /// Check if fluency is good (>= 0.7)
  bool get isGood => score >= 0.7;

  @override
  List<Object?> get props => [score, level, issues];
}

/// Represents vocabulary level analysis
class VocabularyLevel extends Equatable {
  /// CEFR level (A2, B1, B2)
  final String level;

  /// Confidence of the classification (0.0 - 1.0)
  final double confidence;

  /// List of difficult words found
  final List<DifficultWord> difficultWords;

  const VocabularyLevel({
    required this.level,
    required this.confidence,
    required this.difficultWords,
  });

  /// Check if there are difficult words
  bool get hasDifficultWords => difficultWords.isNotEmpty;

  @override
  List<Object?> get props => [level, confidence, difficultWords];
}

/// Represents a grammar error found in the text
class GrammarError extends Equatable {
  /// Type of error (e.g., "verb_tense", "article", "subject_verb_agreement")
  final String errorType;

  /// Human-readable explanation of the error
  final String explanation;

  /// Suggested correction
  final String suggestion;

  /// Start position in the original text
  final int startPos;

  /// End position in the original text
  final int endPos;

  const GrammarError({
    required this.errorType,
    required this.explanation,
    required this.suggestion,
    required this.startPos,
    required this.endPos,
  });

  /// Get the length of the error span
  int get length => endPos - startPos;

  @override
  List<Object?> get props => [
        errorType,
        explanation,
        suggestion,
        startPos,
        endPos,
      ];
}

/// Represents a difficult word that might be above user's level
class DifficultWord extends Equatable {
  /// The difficult word
  final String word;

  /// CEFR level of this word (A2, B1, B2, C1)
  final String level;

  /// Definition/meaning of the word
  final String definition;

  /// Example sentence using this word (optional)
  final String? example;

  const DifficultWord({
    required this.word,
    required this.level,
    required this.definition,
    this.example,
  });

  @override
  List<Object?> get props => [word, level, definition, example];
}
