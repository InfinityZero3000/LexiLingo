import '../repositories/daily_goal_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/streak_repository.dart';

class UpdateDailyProgressUseCase {
  final DailyGoalRepository dailyGoalRepository;
  final UserRepository userRepository;
  final StreakRepository streakRepository;

  UpdateDailyProgressUseCase({
    required this.dailyGoalRepository,
    required this.userRepository,
    required this.streakRepository,
  });

  Future<void> call({
    required String userId,
    required int xpEarned,
    int lessonsCompleted = 0,
    int wordsLearned = 0,
    int minutesSpent = 0,
  }) async {
    // 1. Update daily goal progress
    await dailyGoalRepository.updateDailyProgress(
      userId: userId,
      xpEarned: xpEarned,
      lessonsCompleted: lessonsCompleted,
      wordsLearned: wordsLearned,
      minutesSpent: minutesSpent,
    );

    // 2. Check if goal completed today → mark streak
    final goal = await dailyGoalRepository.getTodayGoal(userId);
    if (goal != null && goal.isCompleted) {
      final today = DateTime.now();
      final streak = await streakRepository.getStreakByDate(userId, today);
      
      // Only mark if not already completed
      if (streak == null || !streak.completed) {
        await streakRepository.markDayComplete(userId, today);
        
        // Update user's current streak
        final currentStreak = await streakRepository.getCurrentStreak(userId);
        final user = await userRepository.getUser(userId);
        if (user != null) {
          final longestStreak = currentStreak > user.longestStreak 
              ? currentStreak 
              : user.longestStreak;
          
          await userRepository.updateUserStats(
            userId: userId,
            currentStreak: currentStreak,
            longestStreak: longestStreak,
          );
        }
      }
    }

    // 3. Update user's total stats
    final user = await userRepository.getUser(userId);
    if (user != null) {
      await userRepository.updateUserStats(
        userId: userId,
        totalXP: user.totalXP + xpEarned,
        totalLessonsCompleted: user.totalLessonsCompleted + lessonsCompleted,
        totalWordsLearned: user.totalWordsLearned + wordsLearned,
      );
    }
  }
}
