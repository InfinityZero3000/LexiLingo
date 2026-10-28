import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_courses_usecase.dart';
import 'package:lexilingo_app/features/course/domain/usecases/get_enrolled_courses_usecase.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/domain/usecases/get_weekly_progress_usecase.dart';

class _Courses implements GetCoursesUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Enrolled implements GetEnrolledCoursesUseCase {
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

  @override
  Future<Either<Failure, WeeklyProgressEntity>> call() async {
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
}
