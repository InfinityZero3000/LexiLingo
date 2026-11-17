import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/features/progress/domain/repositories/progress_repository.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';

class _Repository extends Fake implements ProgressRepository {
  bool fail = false;

  @override
  Future<Either<Failure, StreakEntity>> getMyStreak() async => fail
      ? const Left(ServerFailure('offline'))
      : const Right(
          StreakEntity(
            currentStreak: 12,
            longestStreak: 20,
            totalDaysActive: 40,
            freezeCount: 1,
            isActiveToday: true,
            streakAtRisk: false,
          ),
        );
}

void main() {
  test('a failed refresh keeps the streak already on screen', () async {
    final repository = _Repository();
    final provider = StreakProvider(repository: repository);

    await provider.loadStreak();
    expect(provider.currentStreak, 12);

    repository.fail = true;
    await provider.loadStreak();

    expect(provider.currentStreak, 12);
    expect(provider.errorMessage, isNotNull);
    provider.dispose();
  });

  test('a failed first load shows an empty streak, not a null one', () async {
    final repository = _Repository()..fail = true;
    final provider = StreakProvider(repository: repository);

    await provider.loadStreak();

    expect(provider.hasStreak, isTrue);
    expect(provider.currentStreak, 0);
    provider.dispose();
  });
}
