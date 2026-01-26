/// Comprehensive AI response containing all analysis results
class AIResponse {
  /// Analysis results
  final AnalysisResult analysis;
  
  /// English tutor response
  final String responseEn;
  
  /// Vietnamese explanation (optional, for A2 learners)
  final String? responseVi;
  
  /// Overall confidence score (0.0 to 1.0)
  final double confidence;
  
  /// Processing latency in milliseconds
  final int latencyMs;
  
  /// Which components were used
  final ComponentUsage componentUsage;

  const AIResponse({
    required this.analysis,
    required this.responseEn,
    this.responseVi,
    required this.confidence,
    required this.latencyMs,
    required this.componentUsage,
  });

  Map<String, dynamic> toJson() {
    return {
      'analysis': analysis.toJson(),
      'response_en': responseEn,
      'response_vi': responseVi,
      'confidence': confidence,
      'latency_ms': latencyMs,
      'component_usage': componentUsage.toJson(),
    };
  }

  @override
  String toString() {
    return 'AIResponse(confidence: $confidence, latency: ${latencyMs}ms, '
        'hasVietnamese: ${responseVi != null})';
  }
}

/// Analysis result containing scores and errors
class AnalysisResult {
  final double? fluencyScore;
  final String? vocabularyLevel;
  final List<GrammarError> grammarErrors;
  final PronunciationResult? pronunciation;

  const AnalysisResult({
    this.fluencyScore,
    this.vocabularyLevel,
    required this.grammarErrors,
    this.pronunciation,
  });

  Map<String, dynamic> toJson() {
    return {
      'fluency_score': fluencyScore,
      'vocabulary_level': vocabularyLevel,
      'grammar_errors': grammarErrors.map((e) => e.toJson()).toList(),
      'pronunciation': pronunciation?.toJson(),
    };
  }
}

/// Grammar error details
class GrammarError {
  final String errorType;
  final String incorrect;
  final String correction;
  final String explanation;
  final int? startPos;
  final int? endPos;

  const GrammarError({
    required this.errorType,
    required this.incorrect,
    required this.correction,
    required this.explanation,
    this.startPos,
    this.endPos,
  });

  Map<String, dynamic> toJson() {
    return {
      'error_type': errorType,
      'incorrect': incorrect,
      'correction': correction,
      'explanation': explanation,
      'start_pos': startPos,
      'end_pos': endPos,
    };
  }
}

/// Pronunciation analysis result
class PronunciationResult {
  final double accuracy;
  final List<PhonemeError> errors;
  final double prosodyScore;

  const PronunciationResult({
    required this.accuracy,
    required this.errors,
    required this.prosodyScore,
  });

  Map<String, dynamic> toJson() {
    return {
      'accuracy': accuracy,
      'errors': errors.map((e) => e.toJson()).toList(),
      'prosody_score': prosodyScore,
    };
  }
}

/// Phoneme error details
class PhonemeError {
  final String phoneme;
  final String pronouncedAs;
  final String word;

  const PhonemeError({
    required this.phoneme,
    required this.pronouncedAs,
    required this.word,
  });

  Map<String, dynamic> toJson() {
    return {
      'phoneme': phoneme,
      'pronounced_as': pronouncedAs,
      'word': word,
    };
  }
}

/// Which AI components were used for processing
class ComponentUsage {
  final bool usedQwen;
  final bool usedLLaMA;
  final bool usedHuBERT;
  final bool usedSTT;
  final bool usedTTS;
  final bool usedCache;

  const ComponentUsage({
    required this.usedQwen,
    required this.usedLLaMA,
    required this.usedHuBERT,
    required this.usedSTT,
    required this.usedTTS,
    required this.usedCache,
  });

  Map<String, dynamic> toJson() {
    return {
      'qwen': usedQwen,
      'llama': usedLLaMA,
      'hubert': usedHuBERT,
      'stt': usedSTT,
      'tts': usedTTS,
      'cache': usedCache,
    };
  }

  @override
  String toString() {
    final components = <String>[];
    if (usedQwen) components.add('Qwen');
    if (usedLLaMA) components.add('LLaMA');
    if (usedHuBERT) components.add('HuBERT');
    if (usedSTT) components.add('STT');
    if (usedTTS) components.add('TTS');
    if (usedCache) components.add('Cache');
    return 'Used: ${components.join(", ")}';
  }
}
