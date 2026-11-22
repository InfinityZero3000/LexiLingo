import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:lexilingo_app/features/achievements/domain/usecases/get_recent_badges_usecase.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/user/domain/entities/user_stats_entity.dart';
import 'package:lexilingo_app/features/user/domain/entities/weekly_activity_entity.dart';
import 'package:lexilingo_app/features/user/domain/repositories/user_repository.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_stats_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_weekly_activity_usecase.dart';

class _UserRepo implements UserRepository {
  final stats = Completer<Either<Failure, UserStatsEntity>>();
  final activity = Completer<Either<Failure, List<WeeklyActivityEntity>>>();

  @override
  Future<Either<Failure, UserStatsEntity>> getUserStats() => stats.future;

  @override
  Future<Either<Failure, List<WeeklyActivityEntity>>> getWeeklyActivity() =>
      activity.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BadgeRepo implements AchievementRepository {
  final badges = Completer<List<UserAchievementEntity>>();

  @override
  Future<List<UserAchievementEntity>> getRecentBadges({int limit = 4}) =>
      badges.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

UserAchievementEntity _badge() => UserAchievementEntity(
  id: 'b',
  achievement: const AchievementEntity(
    id: 'b',
    name: 'b',
    description: '',
    conditionType: 'x',
    conditionValue: 1,
    category: 'lesson',
    xpReward: 0,
    gemsReward: 0,
    rarity: 'common',
  ),
  unlockedAt: DateTime(2026, 1, 1),
  progress: 1,
);

void main() {
  test(
    'responses that land after clear() do not repopulate the profile',
    () async {
      final users = _UserRepo();
      final badgeRepo = _BadgeRepo();
      final provider = ProfileProvider(
        getUserStatsUseCase: GetUserStatsUseCase(users),
        getWeeklyActivityUseCase: GetWeeklyActivityUseCase(users),
        getRecentBadgesUseCase: GetRecentBadgesUseCase(repository: badgeRepo),
      );

      final load = provider.loadProfileData();
      provider.clear();

      users.stats.complete(
        const Right(
          UserStatsEntity(
            totalXP: 900,
            currentStreak: 3,
            totalCoursesCompleted: 1,
            totalLessonsCompleted: 2,
            totalVocabularyMastered: 3,
            totalTestsPassed: 0,
            totalCertificatesEarned: 0,
            averageTestScore: 0,
          ),
        ),
      );
      users.activity.complete(const Right([]));
      badgeRepo.badges.complete([_badge()]);
      await load;

      expect(provider.stats, isNull);
      expect(provider.recentBadges, isEmpty);
      expect(provider.isLoadingStats, isFalse);
      expect(provider.isLoadingActivity, isFalse);
      expect(provider.isLoadingBadges, isFalse);
    },
  );

  test('a failure that lands after clear() sets no error', () async {
    final users = _UserRepo();
    final badgeRepo = _BadgeRepo();
    final provider = ProfileProvider(
      getUserStatsUseCase: GetUserStatsUseCase(users),
      getWeeklyActivityUseCase: GetWeeklyActivityUseCase(users),
      getRecentBadgesUseCase: GetRecentBadgesUseCase(repository: badgeRepo),
    );

    final load = provider.loadProfileData();
    provider.clear();
    users.stats.complete(const Left(ServerFailure('boom')));
    users.activity.complete(const Left(ServerFailure('boom')));
    badgeRepo.badges.completeError(Exception('boom'));
    await load;

    expect(provider.statsError, isNull);
    expect(provider.activityError, isNull);
    expect(provider.badgesError, isNull);
  });
}
