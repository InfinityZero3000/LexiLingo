import 'package:equatable/equatable.dart';

/// User Progress Summary Entity
/// Represents user's overall learning progress
class UserProgressSummary extends Equatable {
  final int totalXp;
  final int coursesEnrolled;
  final int coursesCompleted;
  final int lessonsCompleted;
  final int currentStreak;
  final int longestStreak;
  final int achievementsUnlocked;

  const UserProgressSummary({
    required this.totalXp,
    required this.coursesEnrolled,
    required this.coursesCompleted,
    required this.lessonsCompleted,
    required this.currentStreak,
    required this.longestStreak,
    required this.achievementsUnlocked,
  });

  @override
  List<Object?> get props => [
        totalXp,
        coursesEnrolled,
        coursesCompleted,
        lessonsCompleted,
        currentStreak,
        longestStreak,
        achievementsUnlocked,
      ];
}

/// Course Progress Detail Entity
class CourseProgressDetail extends Equatable {
  final String courseId;
  final String courseTitle;
  final double progressPercentage;
  final int lessonsCompleted;
  final int totalLessons;
  final int totalXpEarned;
  final DateTime startedAt;
  final DateTime lastActivityAt;
  final int? estimatedCompletionDays;

  const CourseProgressDetail({
    required this.courseId,
    required this.courseTitle,
    required this.progressPercentage,
    required this.lessonsCompleted,
    required this.totalLessons,
    required this.totalXpEarned,
    required this.startedAt,
    required this.lastActivityAt,
    this.estimatedCompletionDays,
  });

  @override
  List<Object?> get props => [
        courseId,
        courseTitle,
        progressPercentage,
        lessonsCompleted,
        totalLessons,
        totalXpEarned,
        startedAt,
        lastActivityAt,
        estimatedCompletionDays,
      ];
}

/// Unit Progress Entity
class UnitProgressEntity extends Equatable {
  final String unitId;
  final String unitTitle;
  final int totalLessons;
  final int completedLessons;
  final double progressPercentage;

  const UnitProgressEntity({
    required this.unitId,
    required this.unitTitle,
    required this.totalLessons,
    required this.completedLessons,
    required this.progressPercentage,
  });

  @override
  List<Object?> get props => [
        unitId,
        unitTitle,
        totalLessons,
        completedLessons,
        progressPercentage,
      ];
}

/// Lesson Completion Result Entity
class LessonCompletionResult extends Equatable {
  final String lessonId;
  final bool isPassed;
  final double score;
  final double bestScore;
  final int xpEarned;
  final int totalXp;
  final double courseProgress;
  final String message;

  const LessonCompletionResult({
    required this.lessonId,
    required this.isPassed,
    required this.score,
    required this.bestScore,
    required this.xpEarned,
    required this.totalXp,
    required this.courseProgress,
    required this.message,
  });

  @override
  List<Object?> get props => [
        lessonId,
        isPassed,
        score,
        bestScore,
        xpEarned,
        totalXp,
        courseProgress,
        message,
      ];
}

/// Progress Stats Entity
class ProgressStatsEntity extends Equatable {
  final UserProgressSummary summary;
  final List<CourseProgressDetail> courseProgress;

  const ProgressStatsEntity({
    required this.summary,
    required this.courseProgress,
  });

  @override
  List<Object?> get props => [summary, courseProgress];
}

/// Course Progress with Units Entity
class CourseProgressWithUnits extends Equatable {
  final CourseProgressDetail course;
  final List<UnitProgressEntity> unitsProgress;

  const CourseProgressWithUnits({
    required this.course,
    required this.unitsProgress,
  });

  @override
  List<Object?> get props => [course, unitsProgress];
}
