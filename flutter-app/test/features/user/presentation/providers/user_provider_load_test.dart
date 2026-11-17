import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/user/domain/entities/daily_goal.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';
import 'package:lexilingo_app/features/user/domain/entities/user.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_current_streak_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_settings_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_today_goal_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/get_user_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/set_daily_goal_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_daily_progress_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_settings_usecase.dart';
import 'package:lexilingo_app/features/user/domain/usecases/update_user_usecase.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';

class _Stub {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _UpdateUser extends _Stub implements UpdateUserUseCase {}

class _UpdateSettings extends _Stub implements UpdateSettingsUseCase {}

class _SetGoal extends _Stub implements SetDailyGoalUseCase {}

class _UpdateProgress extends _Stub implements UpdateDailyProgressUseCase {}

class _GetUser extends _Stub implements GetUserUseCase {
  @override
  Future<User?> call(String userId) async => User(
    id: userId,
    name: 'Mai',
    email: 'mai@example.com',
    joinDate: DateTime(2026),
  );
}

class _GetSettings extends _Stub implements GetSettingsUseCase {
  @override
  Future<Either<Failure, Settings>> call(String userId) async =>
      const Right(Settings(id: 1, userId: 'u1', dailyGoalXP: 80));
}

class _GetGoal extends _Stub implements GetTodayGoalUseCase {
  @override
  Future<Either<Failure, DailyGoal?>> call(GetTodayGoalParams params) async =>
      const Right(null);
}

class _GetStreak extends _Stub implements GetCurrentStreakUseCase {
  @override
  Future<int> call(String userId) async => 4;
}

void main() {
  test('loadUserData unwraps the Either results instead of throwing', () async {
    final provider = UserProvider(
      getUserUseCase: _GetUser(),
      updateUserUseCase: _UpdateUser(),
      getSettingsUseCase: _GetSettings(),
      updateSettingsUseCase: _UpdateSettings(),
      getTodayGoalUseCase: _GetGoal(),
      setDailyGoalUseCase: _SetGoal(),
      updateDailyProgressUseCase: _UpdateProgress(),
      getCurrentStreakUseCase: _GetStreak(),
    );

    provider.setCurrentUser('u1');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(provider.errorMessage, isNull);
    expect(provider.settings?.dailyGoalXP, 80);
    expect(provider.currentStreak, 4);
    expect(provider.isLoading, isFalse);
  });
}
