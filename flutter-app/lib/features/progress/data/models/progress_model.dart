import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';

/// User Progress Summary Model
class UserProgressSummaryModel extends UserProgressSummary {
  const UserProgressSummaryModel({
    required super.totalXp,
    required super.coursesEnrolled,
    required super.coursesCompleted,
    required super.lessonsCompleted,
    required super.currentStreak,
    required super.longestStreak,
    required super.achievementsUnlocked,
  });

  factory UserProgressSummaryModel.fromJson(Map<String, dynamic> json) {
    return UserProgressSummaryModel(
      totalXp: json['total_xp'] ?? 0,
      coursesEnrolled: json['courses_enrolled'] ?? 0,
      coursesCompleted: json['courses_completed'] ?? 0,
      lessonsCompleted: json['lessons_completed'] ?? 0,
      currentStreak: json['current_streak'] ?? 0,
      longestStreak: json['longest_streak'] ?? 0,
      achievementsUnlocked: json['achievements_unlocked'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_xp': totalXp,
      'courses_enrolled': coursesEnrolled,
      'courses_completed': coursesCompleted,
      'lessons_completed': lessonsCompleted,
      'current_streak': currentStreak,
      'longest_streak': longestStreak,
      'achievements_unlocked': achievementsUnlocked,
    };
  }
}

/// Course Progress Detail Model
class CourseProgressDetailModel extends CourseProgressDetail {
  const CourseProgressDetailModel({
    required super.courseId,
    required super.courseTitle,
    required super.progressPercentage,
    required super.lessonsCompleted,
    required super.totalLessons,
    required super.totalXpEarned,
    required super.startedAt,
    required super.lastActivityAt,
    super.estimatedCompletionDays,
  });

  factory CourseProgressDetailModel.fromJson(Map<String, dynamic> json) {
    return CourseProgressDetailModel(
      courseId: json['course_id'],
      courseTitle: json['course_title'],
      progressPercentage: (json['progress_percentage'] ?? 0.0).toDouble(),
      lessonsCompleted: json['lessons_completed'] ?? 0,
      totalLessons: json['total_lessons'] ?? 0,
      totalXpEarned: json['total_xp_earned'] ?? 0,
      startedAt: DateTime.parse(json['started_at']),
      lastActivityAt: DateTime.parse(json['last_activity_at']),
      estimatedCompletionDays: json['estimated_completion_days'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course_id': courseId,
      'course_title': courseTitle,
      'progress_percentage': progressPercentage,
      'lessons_completed': lessonsCompleted,
      'total_lessons': totalLessons,
      'total_xp_earned': totalXpEarned,
      'started_at': startedAt.toIso8601String(),
      'last_activity_at': lastActivityAt.toIso8601String(),
      'estimated_completion_days': estimatedCompletionDays,
    };
  }
}

/// Unit Progress Model
class UnitProgressModel extends UnitProgressEntity {
  const UnitProgressModel({
    required super.unitId,
    required super.unitTitle,
    required super.totalLessons,
    required super.completedLessons,
    required super.progressPercentage,
  });

  factory UnitProgressModel.fromJson(Map<String, dynamic> json) {
    return UnitProgressModel(
      unitId: json['unit_id'],
      unitTitle: json['unit_title'],
      totalLessons: json['total_lessons'] ?? 0,
      completedLessons: json['completed_lessons'] ?? 0,
      progressPercentage: (json['progress_percentage'] ?? 0.0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'unit_id': unitId,
      'unit_title': unitTitle,
      'total_lessons': totalLessons,
      'completed_lessons': completedLessons,
      'progress_percentage': progressPercentage,
    };
  }
}

/// Lesson Completion Result Model
class LessonCompletionResultModel extends LessonCompletionResult {
  const LessonCompletionResultModel({
    required super.lessonId,
    required super.isPassed,
    required super.score,
    required super.bestScore,
    required super.xpEarned,
    required super.totalXp,
    required super.courseProgress,
    required super.message,
  });

  factory LessonCompletionResultModel.fromJson(Map<String, dynamic> json) {
    return LessonCompletionResultModel(
      lessonId: json['lesson_id'],
      isPassed: json['is_passed'] ?? false,
      score: (json['score'] ?? 0.0).toDouble(),
      bestScore: (json['best_score'] ?? 0.0).toDouble(),
      xpEarned: json['xp_earned'] ?? 0,
      totalXp: json['total_xp'] ?? 0,
      courseProgress: (json['course_progress'] ?? 0.0).toDouble(),
      message: json['message'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lesson_id': lessonId,
      'is_passed': isPassed,
      'score': score,
      'best_score': bestScore,
      'xp_earned': xpEarned,
      'total_xp': totalXp,
      'course_progress': courseProgress,
      'message': message,
    };
  }
}

/// Progress Stats Model
class ProgressStatsModel extends ProgressStatsEntity {
  const ProgressStatsModel({
    required super.summary,
    required super.courseProgress,
  });

  factory ProgressStatsModel.fromJson(Map<String, dynamic> json) {
    return ProgressStatsModel(
      summary: UserProgressSummaryModel.fromJson(json['summary'] ?? {}),
      courseProgress: (json['course_progress'] as List<dynamic>?)
              ?.map((cp) => CourseProgressDetailModel.fromJson(cp))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'summary': (summary as UserProgressSummaryModel).toJson(),
      'course_progress': courseProgress
          .map((cp) => (cp as CourseProgressDetailModel).toJson())
          .toList(),
    };
  }
}

/// Course Progress with Units Model
class CourseProgressWithUnitsModel extends CourseProgressWithUnits {
  const CourseProgressWithUnitsModel({
    required super.course,
    required super.unitsProgress,
  });

  factory CourseProgressWithUnitsModel.fromJson(Map<String, dynamic> json) {
    return CourseProgressWithUnitsModel(
      course: CourseProgressDetailModel.fromJson(json['course'] ?? {}),
      unitsProgress: (json['units_progress'] as List<dynamic>?)
              ?.map((up) => UnitProgressModel.fromJson(up))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'course': (course as CourseProgressDetailModel).toJson(),
      'units_progress': unitsProgress
          .map((up) => (up as UnitProgressModel).toJson())
          .toList(),
    };
  }
}
