import 'package:sqflite/sqflite.dart';
import '../models/streak_model.dart';
import '../../../../core/services/database_helper.dart';

abstract class StreakLocalDataSource {
  Future<int> getCurrentStreak(String userId);
  Future<List<StreakModel>> getStreakHistory(String userId, {int days = 30});
  Future<int> markDayComplete(String userId, DateTime date);
  Future<StreakModel?> getStreakByDate(String userId, DateTime date);
}

class StreakLocalDataSourceImpl implements StreakLocalDataSource {
  final DatabaseHelper databaseHelper;

  StreakLocalDataSourceImpl({required this.databaseHelper});

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<int> getCurrentStreak(String userId) async {
    final db = await databaseHelper.database;
    final today = DateTime.now();
    
    // Count consecutive completed days going backwards from today
    int streak = 0;
    DateTime checkDate = today;
    
    while (true) {
      final dateStr = _formatDate(checkDate);
      final result = await db.query(
        'streaks',
        where: 'userId = ? AND date = ? AND completed = 1',
        whereArgs: [userId, dateStr],
      );
      
      if (result.isEmpty) {
        break;
      }
      
      streak++;
      checkDate = checkDate.subtract(const Duration(days: 1));
      
      // Safety limit
      if (streak > 365) break;
    }
    
    return streak;
  }

  @override
  Future<List<StreakModel>> getStreakHistory(String userId, {int days = 30}) async {
    final db = await databaseHelper.database;
    final endDate = DateTime.now();
    final startDate = endDate.subtract(Duration(days: days));
    
    final List<Map<String, dynamic>> maps = await db.query(
      'streaks',
      where: 'userId = ? AND date >= ? AND date <= ?',
      whereArgs: [userId, _formatDate(startDate), _formatDate(endDate)],
      orderBy: 'date DESC',
    );

    return maps.map((map) => StreakModel.fromJson(map)).toList();
  }

  @override
  Future<int> markDayComplete(String userId, DateTime date) async {
    final db = await databaseHelper.database;

    
    final streak = StreakModel(
      id: 0,
      userId: userId,
      date: date,
      completed: true,
    );
    
    return await db.insert(
      'streaks',
      streak.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<StreakModel?> getStreakByDate(String userId, DateTime date) async {
    final db = await databaseHelper.database;
    final dateStr = _formatDate(date);
    
    final List<Map<String, dynamic>> maps = await db.query(
      'streaks',
      where: 'userId = ? AND date = ?',
      whereArgs: [userId, dateStr],
    );

    if (maps.isEmpty) {
      return null;
    }

    return StreakModel.fromJson(maps.first);
  }
}
