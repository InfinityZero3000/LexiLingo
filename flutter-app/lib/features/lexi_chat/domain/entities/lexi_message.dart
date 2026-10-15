import 'package:lexilingo_app/features/voice/domain/entities/pronunciation_score.dart';

/// Domain entity for a single message in Lexi chat.
class LexiMessage {
  final String id;
  final String role; // 'user' or 'assistant'
  final String content;
  final DateTime timestamp;
  final String? audioBase64;
  final List<LexiCorrection> corrections;
  final List<String> linkedConcepts;
  final LexiSuggestedPractice? suggestedPractice;
  final List<LexiCourseSuggestion> suggestedCourses;
  final String? nativeHint;
  final Map<String, dynamic>? scores;
  final String syncStatus; // 'synced' | 'pending_sync'
  final String? clientRequestId;

  /// Set on the learner's own message when it was sent by voice — the STT
  /// transcript is used as the reference text, so this scores how clearly
  /// they pronounced what they said, not whether it was "correct."
  final PronunciationScore? pronunciationScore;

  const LexiMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.audioBase64,
    this.corrections = const [],
    this.linkedConcepts = const [],
    this.suggestedPractice,
    this.suggestedCourses = const [],
    this.nativeHint,
    this.scores,
    this.syncStatus = 'synced',
    this.clientRequestId,
    this.pronunciationScore,
  });

  bool get isUser => role == 'user';
  bool get isLexi => role == 'assistant';
  bool get hasAudio => audioBase64 != null && audioBase64!.isNotEmpty;
  bool get hasCorrections => corrections.isNotEmpty;
  bool get isPendingSync => syncStatus == 'pending_sync';

  LexiMessage copyWith({
    String? id,
    String? role,
    String? content,
    DateTime? timestamp,
    String? audioBase64,
    List<LexiCorrection>? corrections,
    List<String>? linkedConcepts,
    LexiSuggestedPractice? suggestedPractice,
    List<LexiCourseSuggestion>? suggestedCourses,
    String? nativeHint,
    Map<String, dynamic>? scores,
    String? syncStatus,
    String? clientRequestId,
    PronunciationScore? pronunciationScore,
  }) {
    return LexiMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      audioBase64: audioBase64 ?? this.audioBase64,
      corrections: corrections ?? this.corrections,
      linkedConcepts: linkedConcepts ?? this.linkedConcepts,
      suggestedPractice: suggestedPractice ?? this.suggestedPractice,
      suggestedCourses: suggestedCourses ?? this.suggestedCourses,
      nativeHint: nativeHint ?? this.nativeHint,
      scores: scores ?? this.scores,
      syncStatus: syncStatus ?? this.syncStatus,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      pronunciationScore: pronunciationScore ?? this.pronunciationScore,
    );
  }
}

/// A real course from the catalog, attached by the server when the learner
/// asked what to study. Never parsed out of Lexi's prose — the model can name
/// a course that does not exist, this cannot.
class LexiCourseSuggestion {
  final String courseId;
  final String title;
  final String? level;
  final String? description;
  final String? thumbnailUrl;
  final int totalLessons;
  final int estimatedDuration;

  const LexiCourseSuggestion({
    required this.courseId,
    required this.title,
    this.level,
    this.description,
    this.thumbnailUrl,
    this.totalLessons = 0,
    this.estimatedDuration = 0,
  });

  factory LexiCourseSuggestion.fromJson(Map<String, dynamic> json) {
    return LexiCourseSuggestion(
      courseId: json['course_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      level: json['level']?.toString(),
      description: json['description']?.toString(),
      thumbnailUrl: json['thumbnail_url']?.toString(),
      totalLessons: (json['total_lessons'] as num?)?.toInt() ?? 0,
      estimatedDuration: (json['estimated_duration'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'course_id': courseId,
    'title': title,
    'level': level,
    'description': description,
    'thumbnail_url': thumbnailUrl,
    'total_lessons': totalLessons,
    'estimated_duration': estimatedDuration,
  };
}

/// A one-tap follow-up practice prompt tied to the concept behind the
/// mistake just corrected (not a generic "you're weak at X" suggestion).
class LexiSuggestedPractice {
  final String conceptId;
  final String conceptTitle;
  final String prompt;

  const LexiSuggestedPractice({
    required this.conceptId,
    required this.conceptTitle,
    required this.prompt,
  });
}

/// A grammar/vocabulary correction from Lexi.
class LexiCorrection {
  final String errorSpan;
  final String correction;
  final String errorType;
  final String explanation;

  const LexiCorrection({
    required this.errorSpan,
    required this.correction,
    required this.errorType,
    required this.explanation,
  });
}
