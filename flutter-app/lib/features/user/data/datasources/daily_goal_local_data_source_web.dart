import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'daily_goal_local_data_source.dart';
import '../models/daily_goal_model.dart';

/// Web implementation of DailyGoalLocalDataSource using SharedPreferences
class DailyGoalLocalDataSourceWeb implements DailyGoalLocalDataSource {
  final SharedPreferences sharedPreferences;
  
  static const String _goalKey = 'daily_goal_';
  
  DailyGoalLocalDataSourceWeb({required this.sharedPreferences});

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<DailyGoalModel?> getTodayGoal(String userId) async {
    return getGoalByDate(userId, DateTime.now());
  }

  @override
  Future<DailyGoalModel?> getGoalByDate(String userId, DateTime date) async {
    final dateStr = _formatDate(date);
    final jsonString = sharedPreferences.getString('$_goalKey${userId}_$dateStr');
    if (jsonString != null) {
      return DailyGoalModel.fromJson(json.decode(jsonString));
    }
    return null;
  }

  @override
  Future<List<DailyGoalModel>> getGoalHistory(String userId, {int days = 7}) async {
    final goals = <DailyGoalModel>[];
    final now = DateTime.now();
    
    for (int i = 0; i < days; i++) {
      final date = now.subtract(Duration(days: i));
      final goal = await getGoalByDate(userId, date);
      if (goal != null) {
        goals.add(goal);
      }
    }
    
    return goals;
  }

  @override
  Future<int> createOrUpdateGoal(DailyGoalModel goal) async {
    final dateStr = _formatDate(goal.date);
    await sharedPreferences.setString(
      '$_goalKey${goal.userId}_$dateStr',
      json.encode(goal.toJson()),
    );
    return 1; // Success
  }

  @override
  Future<int> updateDailyProgress({
    required String userId,
    required int xpEarned,
    int lessonsCompleted = 0,
    int wordsLearned = 0,
    int minutesSpent = 0,
  }) async {
    final todayGoal = await getTodayGoal(userId);
    
    if (todayGoal == null) {
      // Create new goal for today
      final newGoal = DailyGoalModel(
        id: DateTime.now().millisecondsSinceEpoch, // Use timestamp as id
        userId: userId,
        date: DateTime.now(),
        targetXP: 50, // Default goal
        earnedXP: xpEarned,
        lessonsCompleted: lessonsCompleted,
        wordsLearned: wordsLearned,
        minutesSpent: minutesSpent,
      );
      return await createOrUpdateGoal(newGoal);
    } else {
      // Update existing goal
      final updatedGoal = DailyGoalModel(
        id: todayGoal.id,
        userId: todayGoal.userId,
        date: todayGoal.date,
        targetXP: todayGoal.targetXP,
        earnedXP: todayGoal.earnedXP + xpEarned,
        lessonsCompleted: todayGoal.lessonsCompleted + lessonsCompleted,
        wordsLearned: todayGoal.wordsLearned + wordsLearned,
        minutesSpent: todayGoal.minutesSpent + minutesSpent,
      );
      return await createOrUpdateGoal(updatedGoal);
    }
  }
}
