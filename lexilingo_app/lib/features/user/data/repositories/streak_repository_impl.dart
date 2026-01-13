import '../../domain/entities/streak.dart';
import '../../domain/repositories/streak_repository.dart';
import '../datasources/streak_local_data_source.dart';

class StreakRepositoryImpl implements StreakRepository {
  final StreakLocalDataSource localDataSource;

  StreakRepositoryImpl({required this.localDataSource});

  @override
  Future<int> getCurrentStreak(String userId) async {
    return await localDataSource.getCurrentStreak(userId);
  }

  @override
  Future<List<Streak>> getStreakHistory(String userId, {int days = 30}) async {
    return await localDataSource.getStreakHistory(userId, days: days);
  }

  @override
  Future<void> markDayComplete(String userId, DateTime date) async {
    await localDataSource.markDayComplete(userId, date);
  }

  @override
  Future<Streak?> getStreakByDate(String userId, DateTime date) async {
    return await localDataSource.getStreakByDate(userId, date);
  }
}
