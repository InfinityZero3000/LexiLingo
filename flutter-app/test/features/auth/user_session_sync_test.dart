import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/auth/presentation/user_session_sync.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/progress/domain/entities/content_activity_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/user_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_my_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_course_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_weekly_progress_usecase.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/content_activity_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:provider/provider.dart';

class _Repository extends Fake implements ProgressRepository {
  int weeklyCalls = 0;
  int streakCalls = 0;
  Completer<void>? gate;

  @override
  Future<Either<Failure, ContentActivityEntity>> getContentActivity({
    int days = 7,
  }) async => const Right(
    ContentActivityEntity(
      days: 7,
      totalMinutes: 42,
      totalSessions: 3,
      totalXp: 30,
      bySource: [],
    ),
  );

  @override
  Future<Either<Failure, WeeklyProgressEntity>> getWeeklyProgress() async {
    weeklyCalls++;
    await gate?.future;
    return Right(
      WeeklyProgressEntity(
        weekProgress: WeeklyProgressEntity.empty().weekProgress,
        totalXP: 104,
        totalLessons: 2,
        totalStudyTime: 0,
        daysActive: 3,
        currentStreak: 3,
        longestStreak: 3,
        weekGoalProgress: 0,
      ),
    );
  }

  @override
  Future<Either<Failure, StreakEntity>> getMyStreak() async {
    streakCalls++;
    return const Right(
      StreakEntity(
        currentStreak: 5,
        longestStreak: 9,
        totalDaysActive: 20,
        freezeCount: 0,
        isActiveToday: true,
        streakAtRisk: false,
      ),
    );
  }

  @override
  Future<Either<Failure, ProgressStatsEntity>> getMyProgress() async =>
      const Right(
        ProgressStatsEntity(
          summary: UserProgressSummary(
            totalXp: 104,
            coursesEnrolled: 1,
            coursesCompleted: 0,
            lessonsCompleted: 2,
            currentStreak: 3,
            longestStreak: 3,
            achievementsUnlocked: 0,
          ),
          courseProgress: [],
        ),
      );
}

class _Api extends Fake implements ApiClient {
  int calls = 0;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    calls++;
    return {'total_xp': 104, 'numeric_level': 3};
  }
}

class _NoCourses extends Fake implements GetCoursesUseCase {}

class _NoEnrolled extends Fake implements GetEnrolledCoursesUseCase {}

void main() {
  late _Repository repository;
  late _Api api;
  late ProgressProvider progress;
  late StreakProvider streak;
  late HomeProvider home;
  late LevelProvider level;
  late ContentActivityProvider content;
  late BuildContext context;

  Future<void> pumpScope(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: progress),
          ChangeNotifierProvider.value(value: streak),
          ChangeNotifierProvider.value(value: home),
          ChangeNotifierProvider.value(value: level),
          ChangeNotifierProvider.value(value: content),
        ],
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  setUp(() {
    repository = _Repository();
    api = _Api();
    progress = ProgressProvider(
      getMyProgressUseCase: GetMyProgressUseCase(repository),
      getCourseProgressUseCase: GetCourseProgressUseCase(repository),
    );
    streak = StreakProvider(repository: repository);
    home = HomeProvider(
      getCoursesUseCase: _NoCourses(),
      getEnrolledCoursesUseCase: _NoEnrolled(),
      getWeeklyProgressUseCase: GetWeeklyProgressUseCase(repository),
    );
    level = LevelProvider(apiClient: api);
    content = ContentActivityProvider(repository: repository);
  });

  testWidgets('signing in loads streak, weekly progress and level', (
    tester,
  ) async {
    await pumpScope(tester);

    await UserSessionSync.afterSignIn(context);

    expect(repository.streakCalls, 1);
    expect(repository.weeklyCalls, 1);
    expect(api.calls, 1);
    expect(home.weeklyProgress.totalXP, 104);
    expect(streak.currentStreak, 5);
    expect(level.totalXp, 104);
  });

  testWidgets('signing out empties every per-user provider', (tester) async {
    await pumpScope(tester);
    await UserSessionSync.afterSignIn(context);
    await progress.fetchMyProgress();
    expect(progress.summary, isNotNull);

    UserSessionSync.afterSignOut(context);

    expect(progress.summary, isNull);
    expect(streak.hasStreak, isFalse);
    expect(home.weeklyProgress.totalXP, 0);
    expect(level.totalXp, 0);
  });

  testWidgets('a weekly response that lands after sign-out is dropped', (
    tester,
  ) async {
    repository.gate = Completer<void>();
    await pumpScope(tester);

    final pending = home.loadWeeklyProgress();
    UserSessionSync.afterSignOut(context);
    repository.gate!.complete();
    await pending;

    expect(home.weeklyProgress.totalXP, 0);
  });

  testWidgets('a progress response that lands after sign-out is dropped', (
    tester,
  ) async {
    await pumpScope(tester);

    final pending = progress.fetchMyProgress();
    UserSessionSync.afterSignOut(context);
    await pending;

    expect(progress.summary, isNull);
  });

  testWidgets('signing out clears the previous learner content minutes', (
    tester,
  ) async {
    await pumpScope(tester);
    await content.load();
    expect(content.activity.totalMinutes, 42);

    UserSessionSync.afterSignOut(context);

    expect(content.activity.totalMinutes, 0);
    expect(content.activity.isEmpty, isTrue);
  });

  testWidgets('a content response that lands after sign-out is dropped', (
    tester,
  ) async {
    await pumpScope(tester);

    final pending = content.load();
    UserSessionSync.afterSignOut(context);
    await pending;

    expect(content.activity.totalMinutes, 0);
  });

  testWidgets('overlapping streak and level loads share one request', (
    tester,
  ) async {
    await pumpScope(tester);

    await Future.wait([
      UserSessionSync.afterSignIn(context),
      streak.loadStreak(),
      level.fetchLevelFull(),
    ]);

    expect(repository.streakCalls, 1);
    expect(api.calls, 1);
  });
}
