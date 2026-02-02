import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';

/// Progress Repository Interface
/// Defines contract for progress tracking operations
///
/// Following agent-skills/language-learning-patterns:
/// - progress-learning-streaks: Streak tracking (3-5x engagement)
abstract class ProgressRepository {
  /// Get user's overall progress statistics
  Future<Either<Failure, ProgressStatsEntity>> getMyProgress();

  /// Get detailed progress for a specific course
  Future<Either<Failure, CourseProgressWithUnits>> getCourseProgress(
    String courseId,
  );

  /// Complete a lesson with score
  Future<Either<Failure, LessonCompletionResult>> completeLesson({
    required String lessonId,
    required double score,
  });

  /// Get user's total XP
  Future<Either<Failure, int>> getTotalXp();

  // ============================================================================
  // Weekly Progress Operations (Task 1.3)
  // ============================================================================

  /// Get weekly progress for home page chart
  /// 
  /// Returns 7-day activity breakdown with totals and streak info.
  /// Used for the week progress visualization component.
  Future<Either<Failure, WeeklyProgressEntity>> getWeeklyProgress();

  // ============================================================================
  // Streak Operations
  // ============================================================================

  /// Get user's current streak information
  Future<Either<Failure, StreakEntity>> getMyStreak();

  /// Update streak after learning activity
  Future<Either<Failure, StreakUpdateResult>> updateStreak();

  /// Use a streak freeze to protect current streak
  Future<Either<Failure, Map<String, dynamic>>> useStreakFreeze();

  // ============================================================================
  // Daily Challenges Operations
  // ============================================================================

  /// Get today's daily challenges
  Future<Either<Failure, DailyChallengesResponse>> getDailyChallenges();

  /// Claim reward for a completed challenge
  Future<Either<Failure, Map<String, dynamic>>> claimChallengeReward(
    String challengeId,
  );
}
