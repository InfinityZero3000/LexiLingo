import '../repositories/user_repository.dart';

class UpdateUserStatsUseCase {
  final UserRepository repository;

  UpdateUserStatsUseCase({required this.repository});

  Future<void> call({
    required String userId,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  }) async {
    await repository.updateUserStats(
      userId: userId,
      totalXP: totalXP,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalLessonsCompleted: totalLessonsCompleted,
      totalWordsLearned: totalWordsLearned,
    );
  }
}
