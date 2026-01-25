import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';

/// Progress Repository Interface
/// Defines contract for progress tracking operations
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
}
