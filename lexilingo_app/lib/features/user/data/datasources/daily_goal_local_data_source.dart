import 'package:sqflite/sqflite.dart';
import '../models/daily_goal_model.dart';
import '../../../../core/services/database_helper.dart';

abstract class DailyGoalLocalDataSource {
  Future<DailyGoalModel?> getTodayGoal(String userId);
  Future<DailyGoalModel?> getGoalByDate(String userId, DateTime date);
  Future<List<DailyGoalModel>> getGoalHistory(String userId, {int days = 7});
  Future<int> createOrUpdateGoal(DailyGoalModel goal);
  Future<int> updateDailyProgress({
    required String userId,
    required int xpEarned,
    int lessonsCompleted = 0,
    int wordsLearned = 0,
    int minutesSpent = 0,
  });
}

class DailyGoalLocalDataSourceImpl implements DailyGoalLocalDataSource {
  final DatabaseHelper databaseHelper;

  DailyGoalLocalDataSourceImpl({required this.databaseHelper});

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<DailyGoalModel?> getTodayGoal(String userId) async {
    return getGoalByDate(userId, DateTime.now());
  }

  @override
  Future<DailyGoalModel?> getGoalByDate(String userId, DateTime date) async {
    final db = await databaseHelper.database;
    final dateStr = _formatDate(date);
    
    final List<Map<String, dynamic>> maps = await db.query(
      'daily_goals',
      where: 'userId = ? AND date = ?',
      whereArgs: [userId, dateStr],
    );

    if (maps.isEmpty) {
      return null;
    }

    return DailyGoalModel.fromJson(maps.first);
  }

  @override
  Future<List<DailyGoalModel>> getGoalHistory(String userId, {int days = 7}) async {
    final db = await databaseHelper.database;
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days));
    
    final List<Map<String, dynamic>> maps = await db.query(
      'daily_goals',
      where: 'userId = ? AND date >= ? AND date <= ?',
      whereArgs: [userId, _formatDate(startDate), _formatDate(endDate)],
      orderBy: 'date DESC',
    );

    return maps.map((map) => DailyGoalModel.fromJson(map)).toList();
  }

  @override
  Future<int> createOrUpdateGoal(DailyGoalModel goal) async {
    final db = await databaseHelper.database;
    return await db.insert(
      'daily_goals',
      goal.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> updateDailyProgress({
    required String userId,
    required int xpEarned,
    int lessonsCompleted = 0,
    int wordsLearned = 0,
    int minutesSpent = 0,
  }) async {
    // Get current goal or create new one
    final existing = await getTodayGoal(userId);
    
    if (existing == null) {
      // Create new goal with default target
      final newGoal = DailyGoalModel(
        id: 0,
        userId: userId,
        date: DateTime.now(),
        targetXP: 50,
        earnedXP: xpEarned,
        lessonsCompleted: lessonsCompleted,
        wordsLearned: wordsLearned,
        minutesSpent: minutesSpent,
      );
      return await createOrUpdateGoal(newGoal);
    } else {
      // Update existing goal
      final updated = DailyGoalModel(
        id: existing.id,
        userId: existing.userId,
        date: existing.date,
        targetXP: existing.targetXP,
        earnedXP: existing.earnedXP + xpEarned,
        lessonsCompleted: existing.lessonsCompleted + lessonsCompleted,
        wordsLearned: existing.wordsLearned + wordsLearned,
        minutesSpent: existing.minutesSpent + minutesSpent,
      );
      return await createOrUpdateGoal(updated);
    }
  }
}
