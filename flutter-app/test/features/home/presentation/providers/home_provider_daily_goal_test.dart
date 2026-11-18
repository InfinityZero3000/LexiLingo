import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/user/domain/entities/user.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_weekly_progress_usecase.dart';

final _course = CourseEntity(
  id: 'c1',
  title: 'Everyday English',
  language: 'en',
  level: 'intermediate',
  tags: const [],
  totalXp: 0,
  estimatedDuration: 0,
  totalLessons: 12,
  isPublished: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

class _Courses implements GetCoursesUseCase {
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> call(
    GetCoursesParams params,
  ) async {
    await gate?.future;
    return fail ? const Left(ServerFailure('offline')) : Right(([_course], 1));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Enrolled implements GetEnrolledCoursesUseCase {
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<Either<Failure, (List<CourseEntity>, int)>> call({
    int page = 1,
    int pageSize = 20,
  }) async {
    await gate?.future;
    return fail ? const Left(ServerFailure('offline')) : Right(([_course], 1));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo implements ProgressRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWeekly extends GetWeeklyProgressUseCase {
  _FakeWeekly(this.xpToday) : super(_Repo());
  int xpToday;
  bool fail = false;
  int calls = 0;

  @override
  Future<Either<Failure, WeeklyProgressEntity>> call() async {
    calls++;
    await Future<void>.delayed(Duration.zero);
    if (fail) return const Left(ServerFailure('offline'));
    final now = DateTime.now();
    return Right(
      WeeklyProgressEntity(
        weekProgress: [
          DailyProgressEntity(
            day: 'Thu',
            date: now,
            xpEarned: xpToday,
            lessonsCompleted: 1,
            studyTimeMinutes: 0,
            vocabularyReviewed: 0,
            goalMet: false,
            isToday: true,
          ),
        ],
        totalXP: xpToday,
        totalLessons: 1,
        totalStudyTime: 0,
        daysActive: 1,
        currentStreak: 1,
        longestStreak: 1,
        weekGoalProgress: 0,
      ),
    );
  }
}

void main() {
  test('changing the daily goal keeps the XP already earned today', () async {
    final weekly = _FakeWeekly(80);
    final provider = HomeProvider(
      getCoursesUseCase: _Courses(),
      getEnrolledCoursesUseCase: _Enrolled(),
      getWeeklyProgressUseCase: weekly,
    );
    await provider.loadWeeklyProgress();

    provider.updateDailyGoalTarget(200);
    expect(provider.dailyXP, 80);
    expect(provider.dailyGoalXP, 200);
    expect(provider.dailyProgressPercentage, 0.4);

    weekly.xpToday = 120;
    await provider.loadWeeklyProgress();
    expect(provider.dailyXP, 120);
  });

  test('refreshing the dashboard keeps the goal the learner chose', () async {
    final provider = HomeProvider(
      getCoursesUseCase: _Courses(),
      getEnrolledCoursesUseCase: _Enrolled(),
    );
    final user = User(
      id: 'u1',
      name: 'Lan',
      email: 'lan@example.com',
      joinDate: DateTime.utc(2026, 1, 1),
    );
    await provider.loadDashboard(user);
    provider.updateDailyGoalTarget(200);

    await provider.loadDashboard(user);

    expect(provider.dailyGoalXP, 200);
  });

  test('a failed weekly refresh keeps the streak already shown', () async {
    final weekly = _FakeWeekly(80);
    final provider = HomeProvider(
      getCoursesUseCase: _Courses(),
      getEnrolledCoursesUseCase: _Enrolled(),
      getWeeklyProgressUseCase: weekly,
    );
    await provider.loadWeeklyProgress();
    weekly.fail = true;

    await provider.loadWeeklyProgress();

    expect(provider.streakDays, 1);
  });

  test('a failed refresh keeps the courses already loaded', () async {
    final courses = _Courses();
    final enrolled = _Enrolled();
    final provider = HomeProvider(
      getCoursesUseCase: courses,
      getEnrolledCoursesUseCase: enrolled,
    );
    await provider.loadHomeData();
    expect(provider.featuredCourses, hasLength(1));

    courses.fail = true;
    enrolled.fail = true;
    await provider.loadHomeData();

    expect(provider.featuredCourses, hasLength(1));
    expect(provider.enrolledCourses, hasLength(1));
    expect(provider.errorMessage, 'offline');
    expect(provider.enrolledError, 'offline');
  });

  test('daily XP is unknown until weekly progress arrives', () async {
    final provider = HomeProvider(
      getCoursesUseCase: _Courses(),
      getEnrolledCoursesUseCase: _Enrolled(),
      getWeeklyProgressUseCase: _FakeWeekly(30),
    );
    expect(provider.hasDailyXP, isFalse);
    await provider.loadWeeklyProgress();
    expect(provider.hasDailyXP, isTrue);
    expect(provider.dailyXP, 30);
  });

  test('courses that land after clear() are dropped', () async {
    final courses = _Courses()..gate = Completer<void>();
    final enrolled = _Enrolled()..gate = Completer<void>();
    final provider = HomeProvider(
      getCoursesUseCase: courses,
      getEnrolledCoursesUseCase: enrolled,
    );

    final featured = provider.loadFeaturedCourses();
    final mine = provider.loadEnrolledCourses();
    provider.clear();
    courses.gate!.complete();
    enrolled.gate!.complete();
    await featured;
    await mine;

    expect(provider.featuredCourses, isEmpty);
    expect(provider.enrolledCourses, isEmpty);
  });

  test('concurrent weekly loads share one request', () async {
    final weekly = _FakeWeekly(80);
    final provider = HomeProvider(
      getCoursesUseCase: _Courses(),
      getEnrolledCoursesUseCase: _Enrolled(),
      getWeeklyProgressUseCase: weekly,
    );

    await Future.wait([
      provider.loadWeeklyProgress(),
      provider.loadWeeklyProgress(),
    ]);
    expect(weekly.calls, 1);

    await provider.loadWeeklyProgress();
    expect(weekly.calls, 2);
  });
}
