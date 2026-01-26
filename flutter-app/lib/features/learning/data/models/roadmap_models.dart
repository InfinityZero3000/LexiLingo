import 'package:freezed_annotation/freezed_annotation.dart';

part 'roadmap_models.freezed.dart';
part 'roadmap_models.g.dart';

/// Lesson progress item for roadmap visualization
@freezed
class LessonProgressItem with _$LessonProgressItem {
  const factory LessonProgressItem({
    required String lessonId,
    required int lessonNumber,
    required String title,
    String? description,
    required bool isLocked,
    required bool isCurrent,
    required bool isCompleted,
    double? bestScore,
    @Default(0) int starsEarned,
    @Default(0) int attemptsCount,
    @Default(0.0) double completionPercentage,
    String? iconUrl,
    @Default('#2196F3') String backgroundColor,
  }) = _LessonProgressItem;

  factory LessonProgressItem.fromJson(Map<String, dynamic> json) =>
      _$LessonProgressItemFromJson(json);
}

/// Unit progress for roadmap
@freezed
class UnitProgressRoadmap with _$UnitProgressRoadmap {
  const factory UnitProgressRoadmap({
    required String unitId,
    required int unitNumber,
    required String title,
    String? description,
    required int totalLessons,
    required int completedLessons,
    required double completionPercentage,
    required bool isCurrent,
    required List<LessonProgressItem> lessons,
    String? iconUrl,
    @Default('#2196F3') String backgroundColor,
  }) = _UnitProgressRoadmap;

  factory UnitProgressRoadmap.fromJson(Map<String, dynamic> json) =>
      _$UnitProgressRoadmapFromJson(json);
}

/// Complete course roadmap response
@freezed
class CourseRoadmapResponse with _$CourseRoadmapResponse {
  const factory CourseRoadmapResponse({
    required String courseId,
    required String courseTitle,
    required String level,
    required int totalUnits,
    required int completedUnits,
    required int totalLessons,
    required int completedLessons,
    required double completionPercentage,
    required int totalXpEarned,
    required int currentStreak,
    required List<UnitProgressRoadmap> units,
  }) = _CourseRoadmapResponse;

  factory CourseRoadmapResponse.fromJson(Map<String, dynamic> json) =>
      _$CourseRoadmapResponseFromJson(json);
}

/// Lesson start request
@freezed
class LessonStartRequest with _$LessonStartRequest {
  const factory LessonStartRequest({
    required String lessonId,
  }) = _LessonStartRequest;

  factory LessonStartRequest.fromJson(Map<String, dynamic> json) =>
      _$LessonStartRequestFromJson(json);
}

/// Lesson start response
@freezed
class LessonStartResponse with _$LessonStartResponse {
  const factory LessonStartResponse({
    required String attemptId,
    required String lessonId,
    required DateTime startedAt,
    required int totalQuestions,
    @Default(3) int livesRemaining,
    @Default(3) int hintsAvailable,
  }) = _LessonStartResponse;

  factory LessonStartResponse.fromJson(Map<String, dynamic> json) =>
      _$LessonStartResponseFromJson(json);
}

/// Question type enum
enum QuestionType {
  @JsonValue('multiple_choice')
  multipleChoice,
  @JsonValue('fill_blank')
  fillBlank,
  @JsonValue('matching')
  matching,
  @JsonValue('listening')
  listening,
  @JsonValue('speaking')
  speaking,
  @JsonValue('translation')
  translation,
}

/// Answer submit request
@freezed
class AnswerSubmitRequest with _$AnswerSubmitRequest {
  const factory AnswerSubmitRequest({
    required String questionId,
    required QuestionType questionType,
    required dynamic userAnswer, // Can be String or Map
    required int timeSpentMs,
    @Default(false) bool hintUsed,
    double? confidenceScore,
  }) = _AnswerSubmitRequest;

  factory AnswerSubmitRequest.fromJson(Map<String, dynamic> json) =>
      _$AnswerSubmitRequestFromJson(json);
}

/// Answer submit response
@freezed
class AnswerSubmitResponse with _$AnswerSubmitResponse {
  const factory AnswerSubmitResponse({
    required String questionAttemptId,
    required bool isCorrect,
    dynamic correctAnswer,
    String? explanation,
    @Default(0) int xpEarned,
    required int livesRemaining,
    required int hintsRemaining,
    required double currentScore,
  }) = _AnswerSubmitResponse;

  factory AnswerSubmitResponse.fromJson(Map<String, dynamic> json) =>
      _$AnswerSubmitResponseFromJson(json);
}

/// Lesson complete request
@freezed
class LessonCompleteRequest with _$LessonCompleteRequest {
  const factory LessonCompleteRequest({
    required String attemptId,
  }) = _LessonCompleteRequest;

  factory LessonCompleteRequest.fromJson(Map<String, dynamic> json) =>
      _$LessonCompleteRequestFromJson(json);
}

/// Lesson complete response
@freezed
class LessonCompleteResponse with _$LessonCompleteResponse {
  const factory LessonCompleteResponse({
    required String attemptId,
    required bool passed,
    required double finalScore,
    required int totalXpEarned,
    required int timeSpentSeconds,
    required double accuracy,
    required int starsEarned,
    String? nextLessonUnlocked,
    @Default([]) List<String> achievementsUnlocked,
    required int totalQuestions,
    required int correctAnswers,
    required int wrongAnswers,
    required int hintsUsed,
  }) = _LessonCompleteResponse;

  factory LessonCompleteResponse.fromJson(Map<String, dynamic> json) =>
      _$LessonCompleteResponseFromJson(json);
}
