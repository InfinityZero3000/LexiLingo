import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'streak_local_data_source.dart';
import '../models/streak_model.dart';

/// Web implementation of StreakLocalDataSource using SharedPreferences
class StreakLocalDataSourceWeb implements StreakLocalDataSource {
  final SharedPreferences sharedPreferences;
  
  static const String _historyKey = 'streak_history_';
  
  StreakLocalDataSourceWeb({required this.sharedPreferences});

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<int> getCurrentStreak(String userId) async {
    // Count consecutive completed days going backwards from today
    final history = await getStreakHistory(userId, days: 365);
    if (history.isEmpty) return 0;
    
    int streak = 0;
    final today = DateTime.now();
    DateTime checkDate = today;
    
    while (true) {
      final dateStr = _formatDate(checkDate);
      bool foundCompleted = false;
      
      for (final record in history) {
        if (_formatDate(record.date) == dateStr && record.completed) {
          foundCompleted = true;
          streak++;
          break;
        }
      }
      
      if (!foundCompleted) break;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }
    
    return streak;
  }

  @override
  Future<List<StreakModel>> getStreakHistory(String userId, {int days = 30}) async {
    final jsonString = sharedPreferences.getString('$_historyKey$userId');
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      final streaks = jsonList
          .map((json) => StreakModel.fromJson(json))
          .toList();
      
      // Return only last N days
      if (streaks.length > days) {
        return streaks.sublist(streaks.length - days);
      }
      return streaks;
    }
    return [];
  }

  @override
  Future<int> markDayComplete(String userId, DateTime date) async {
    // Get the existing streak for this date
    final existingStreak = await getStreakByDate(userId, date);
    if (existingStreak != null && existingStreak.completed) {
      return await getCurrentStreak(userId); // Already marked
    }
    
    // Save the new streak record
    final newStreak = StreakModel(
      id: DateTime.now().millisecondsSinceEpoch,
      userId: userId,
      date: date,
      completed: true,
    );
    
    // Update history
    final history = await getStreakHistory(userId, days: 365);
    history.add(newStreak);
    
    await sharedPreferences.setString(
      '$_historyKey$userId',
      json.encode(history.map((s) => s.toJson()).toList()),
    );
    
    return await getCurrentStreak(userId);
  }

  @override
  Future<StreakModel?> getStreakByDate(String userId, DateTime date) async {
    final dateStr = _formatDate(date);
    final history = await getStreakHistory(userId, days: 365);
    
    for (final streak in history) {
      if (_formatDate(streak.date) == dateStr) {
        return streak;
      }
    }
    
    return null;
  }
}
