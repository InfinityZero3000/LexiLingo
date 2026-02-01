/// Get Weekly Progress Use Case
/// 
/// Following agent-skills/language-learning-patterns:
/// - progress-learning-streaks: Visual progress tracking (3-5x engagement boost)
/// 
/// Retrieves 7-day progress summary for home page chart.
library;

import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';

class GetWeeklyProgressUseCase {
  final ProgressRepository repository;

  GetWeeklyProgressUseCase(this.repository);

  /// Execute the use case to fetch weekly progress
  /// 
  /// Returns:
  /// - WeeklyProgressEntity with 7-day activity data
  /// - Failure if API call fails
  Future<Either<Failure, WeeklyProgressEntity>> call() async {
    return await repository.getWeeklyProgress();
  }
}
