class MistakeNotebookEntry {
  final String id;
  final String sourceType;
  final String sourceId;
  final String sourceTitle;
  final String question;
  final String selectedAnswer;
  final String correctAnswer;
  final String explanation;
  final String skill;
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final int reviewCount;

  const MistakeNotebookEntry({
    required this.id,
    required this.sourceType,
    required this.sourceId,
    required this.sourceTitle,
    required this.question,
    required this.selectedAnswer,
    required this.correctAnswer,
    required this.explanation,
    required this.skill,
    required this.createdAt,
    this.reviewedAt,
    this.reviewCount = 0,
  });

  bool get isReviewed => reviewedAt != null;

  MistakeNotebookEntry copyWith({
    String? id,
    String? sourceType,
    String? sourceId,
    String? sourceTitle,
    String? question,
    String? selectedAnswer,
    String? correctAnswer,
    String? explanation,
    String? skill,
    DateTime? createdAt,
    DateTime? reviewedAt,
    bool clearReviewedAt = false,
    int? reviewCount,
  }) {
    return MistakeNotebookEntry(
      id: id ?? this.id,
      sourceType: sourceType ?? this.sourceType,
      sourceId: sourceId ?? this.sourceId,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      question: question ?? this.question,
      selectedAnswer: selectedAnswer ?? this.selectedAnswer,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      explanation: explanation ?? this.explanation,
      skill: skill ?? this.skill,
      createdAt: createdAt ?? this.createdAt,
      reviewedAt: clearReviewedAt ? null : reviewedAt ?? this.reviewedAt,
      reviewCount: reviewCount ?? this.reviewCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'source_type': sourceType,
    'source_id': sourceId,
    'source_title': sourceTitle,
    'question': question,
    'selected_answer': selectedAnswer,
    'correct_answer': correctAnswer,
    'explanation': explanation,
    'skill': skill,
    'created_at': createdAt.toIso8601String(),
    'reviewed_at': reviewedAt?.toIso8601String(),
    'review_count': reviewCount,
  };

  factory MistakeNotebookEntry.fromJson(Map<String, dynamic> json) {
    return MistakeNotebookEntry(
      id: json['id'] as String? ?? '',
      sourceType: json['source_type'] as String? ?? '',
      sourceId: json['source_id'] as String? ?? '',
      sourceTitle: json['source_title'] as String? ?? '',
      question: json['question'] as String? ?? '',
      selectedAnswer: json['selected_answer'] as String? ?? '',
      correctAnswer: json['correct_answer'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      skill: json['skill'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      reviewedAt: DateTime.tryParse(json['reviewed_at'] as String? ?? ''),
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// Identity is the question, not the wrong answer: getting the same
  /// question wrong twice with two different wrong answers must update one
  /// notebook entry, not create a second one next to it. The backend's own
  /// dedup (source_type + source_id + question hash) already ignores the
  /// selected answer; this used to include it, so repeating a mistake with a
  /// different wrong answer minted a new id the backend then merged away —
  /// leaving a stale duplicate in the local cache.
  static String buildId({
    required String sourceType,
    required String sourceId,
    required String questionId,
  }) {
    final raw = '$sourceType|$sourceId|$questionId';
    return 'mistake_${_stableHash(raw).toRadixString(16)}';
  }

  static int _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
