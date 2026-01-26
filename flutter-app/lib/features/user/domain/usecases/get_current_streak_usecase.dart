import '../repositories/streak_repository.dart';

class GetCurrentStreakUseCase {
  final StreakRepository repository;

  GetCurrentStreakUseCase({required this.repository});

  Future<int> call(String userId) async {
    return await repository.getCurrentStreak(userId);
  }
}
