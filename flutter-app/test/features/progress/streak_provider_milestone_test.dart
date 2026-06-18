import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';

/// Minimal stub — only updateStreak is called in these tests.
class _StubProgressRepository implements ProgressRepository {
  final StreakUpdateResult updateResult;

  _StubProgressRepository(this.updateResult);

  @override
  Future<Either<Failure, StreakUpdateResult>> updateStreak() async =>
      Right(updateResult);

  @override
  Future<Either<Failure, StreakEntity>> getMyStreak() async => Right(
        StreakEntity(
          currentStreak: updateResult.currentStreak,
          longestStreak: updateResult.longestStreak,
          totalDaysActive: updateResult.totalDaysActive,
          lastActivityDate: DateTime.now().toIso8601String(),
          freezeCount: updateResult.freezeCount,
          isActiveToday: true,
          streakAtRisk: false,
        ),
      );

  @override
  Future<Either<Failure, ProgressStatsEntity>> getMyProgress() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, CourseProgressWithUnits>> getCourseProgress(
          String courseId) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, LessonCompletionResult>> completeLesson({
    required String lessonId,
    required double score,
  }) async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> getTotalXp() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, WeeklyProgressEntity>> getWeeklyProgress() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Map<String, dynamic>>> useStreakFreeze() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, StreakEntity>> restoreStreak() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Map<String, dynamic>>> claimDailyReward() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, DailyChallengesResponse>> getDailyChallenges() async =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Map<String, dynamic>>> claimChallengeReward(
          String challengeId) async =>
      throw UnimplementedError();
}

StreakUpdateResult _result(int streak) => StreakUpdateResult(
      currentStreak: streak,
      longestStreak: streak,
      totalDaysActive: streak,
      freezeCount: 0,
      streakIncreased: true,
      streakSaved: false,
    );

void main() {
  group('StreakProvider.milestoneJustReached', () {
    for (final days in [7, 14, 30, 60, 100, 365]) {
      test('is true when streak hits $days days', () async {
        final provider = StreakProvider(
          repository: _StubProgressRepository(_result(days)),
        );
        // Pre-load a streak so the entity exists for isMilestone check
        await provider.loadStreak();
        await provider.updateStreak();

        expect(provider.milestoneJustReached, isTrue);
        expect(provider.currentStreak, days);
        provider.dispose();
      });
    }

    for (final days in [1, 5, 10, 15, 50, 99]) {
      test('is false when streak is $days days (non-milestone)', () async {
        final provider = StreakProvider(
          repository: _StubProgressRepository(_result(days)),
        );
        await provider.loadStreak();
        await provider.updateStreak();

        expect(provider.milestoneJustReached, isFalse);
        provider.dispose();
      });
    }

    test('clearMilestone resets the flag to false', () async {
      final provider = StreakProvider(
        repository: _StubProgressRepository(_result(7)),
      );
      await provider.loadStreak();
      await provider.updateStreak();
      expect(provider.milestoneJustReached, isTrue);

      provider.clearMilestone();
      expect(provider.milestoneJustReached, isFalse);
      provider.dispose();
    });

    test('flag is false when streakIncreased is false', () async {
      final result = StreakUpdateResult(
        currentStreak: 7,
        longestStreak: 7,
        totalDaysActive: 7,
        freezeCount: 0,
        streakIncreased: false, // already updated today
        streakSaved: false,
      );
      final provider = StreakProvider(
        repository: _StubProgressRepository(result),
      );
      await provider.loadStreak();
      await provider.updateStreak();

      expect(provider.milestoneJustReached, isFalse);
      provider.dispose();
    });
  });

  group('StreakEntity.isMilestone', () {
    StreakEntity _entity(int streak) => StreakEntity(
          currentStreak: streak,
          longestStreak: streak,
          totalDaysActive: streak,
          lastActivityDate: DateTime.now().toIso8601String(),
          freezeCount: 0,
          isActiveToday: true,
          streakAtRisk: false,
        );

    for (final days in [7, 14, 30, 60, 100, 365]) {
      test('returns true for $days days', () {
        expect(_entity(days).isMilestone, isTrue);
      });
    }

    for (final days in [1, 6, 8, 29, 31, 101]) {
      test('returns false for $days days', () {
        expect(_entity(days).isMilestone, isFalse);
      });
    }
  });
}
