import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/utils/freshness.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_course_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_my_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_weekly_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';

class _Api extends Fake implements ApiClient {
  int calls = 0;
  Completer<void>? gate;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    calls++;
    await gate?.future;
    return {'total_xp': 10, 'rank': 'bronze'};
  }
}

class _Stats extends Fake implements ProgressStatsEntity {}

class _Repo extends Fake implements ProgressRepository {
  int streakCalls = 0;
  int weeklyCalls = 0;
  int myProgressCalls = 0;
  Completer<void>? gate;

  @override
  Future<Either<Failure, StreakEntity>> getMyStreak() async {
    streakCalls++;
    await gate?.future;
    return const Right(
      StreakEntity(
        currentStreak: 3,
        longestStreak: 3,
        totalDaysActive: 3,
        freezeCount: 0,
        isActiveToday: false,
        streakAtRisk: false,
      ),
    );
  }

  @override
  Future<Either<Failure, WeeklyProgressEntity>> getWeeklyProgress() async {
    weeklyCalls++;
    await gate?.future;
    return Right(WeeklyProgressEntity.empty());
  }

  @override
  Future<Either<Failure, ProgressStatsEntity>> getMyProgress() async {
    myProgressCalls++;
    await gate?.future;
    return Right(_Stats());
  }
}

class _Courses extends Fake implements GetCoursesUseCase {}

class _Enrolled extends Fake implements GetEnrolledCoursesUseCase {}

void main() {
  const window = kPassiveReloadWindow;

  group('users/me/level-full', () {
    test('concurrent loads share one request', () async {
      final api = _Api()..gate = Completer<void>();
      final provider = LevelProvider(apiClient: api);

      final a = provider.fetchLevelFull(maxAge: window);
      final b = provider.fetchLevelFull(maxAge: window);
      api.gate!.complete();
      await Future.wait([a, b]);

      expect(api.calls, 1);
    });

    test('a passive reload inside the window makes no request', () async {
      final api = _Api();
      final provider = LevelProvider(apiClient: api);

      await provider.fetchLevelFull(maxAge: window);
      await provider.fetchLevelFull(maxAge: window);

      expect(api.calls, 1);
    });

    test('an explicit refresh always fetches', () async {
      final api = _Api();
      final provider = LevelProvider(apiClient: api);

      await provider.fetchLevelFull(maxAge: window);
      await provider.fetchLevelFull();

      expect(api.calls, 2);
    });

    test('reset (user switch) drops freshness', () async {
      final api = _Api();
      final provider = LevelProvider(apiClient: api);

      await provider.fetchLevelFull(maxAge: window);
      provider.reset();
      await provider.fetchLevelFull(maxAge: window);

      expect(api.calls, 2);
    });
  });

  group('progress/streak', () {
    test('share, stay fresh, explicit refetch, reset refetch', () async {
      final repo = _Repo()..gate = Completer<void>();
      final provider = StreakProvider(repository: repo);

      final a = provider.loadStreak(maxAge: window);
      final b = provider.loadStreak(maxAge: window);
      repo.gate!.complete();
      await Future.wait([a, b]);
      await provider.loadStreak(maxAge: window);
      expect(repo.streakCalls, 1);

      await provider.loadStreak();
      expect(repo.streakCalls, 2);

      provider.reset();
      await provider.loadStreak(maxAge: window);
      expect(repo.streakCalls, 3);
      provider.dispose();
    });
  });

  group('progress/weekly', () {
    test('load and silent refresh share one request, then stay fresh', () async {
      final repo = _Repo()..gate = Completer<void>();
      final provider = HomeProvider(
        getCoursesUseCase: _Courses(),
        getEnrolledCoursesUseCase: _Enrolled(),
        getWeeklyProgressUseCase: GetWeeklyProgressUseCase(repo),
      );

      final a = provider.loadWeeklyProgress(maxAge: window);
      final b = provider.refreshWeeklyProgressSilently(maxAge: window);
      repo.gate!.complete();
      await Future.wait([a, b]);
      await provider.refreshWeeklyProgressSilently(maxAge: window);
      expect(repo.weeklyCalls, 1);

      await provider.loadWeeklyProgress();
      expect(repo.weeklyCalls, 2);

      provider.clear();
      await provider.loadWeeklyProgress(maxAge: window);
      expect(repo.weeklyCalls, 3);
    });
  });

  group('progress/me', () {
    test('share one request; invalidate forces a refetch', () async {
      final repo = _Repo()..gate = Completer<void>();
      final provider = ProgressProvider(
        getMyProgressUseCase: GetMyProgressUseCase(repo),
        getCourseProgressUseCase: GetCourseProgressUseCase(repo),
      );

      final a = provider.fetchMyProgress(maxAge: window);
      final b = provider.fetchMyProgress();
      repo.gate!.complete();
      await Future.wait([a, b]);
      expect(repo.myProgressCalls, 1);

      await provider.fetchMyProgress(maxAge: window);
      expect(repo.myProgressCalls, 1);

      provider.invalidateFreshness();
      await provider.fetchMyProgress(maxAge: window);
      expect(repo.myProgressCalls, 2);
    });
  });
}
