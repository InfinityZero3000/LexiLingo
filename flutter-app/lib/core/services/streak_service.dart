import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';
import '../utils/app_logger.dart';

/// Service to manage user streaks and daily activity
/// Implements real streak logic (not hardcoded)
class StreakService {
  final DatabaseHelper _dbHelper;

  StreakService({DatabaseHelper? dbHelper})
      : _dbHelper = dbHelper ?? DatabaseHelper.instance;

  /// Get current streak for a user
  /// Calculates consecutive days of activity
  Future<int> getCurrentStreak(String userId) async {
    final db = await _dbHelper.database;
    
    // Get all completed days ordered by date descending
    final results = await db.query(
      'streaks',
      where: 'userId = ? AND completed = 1',
      whereArgs: [userId],
      orderBy: 'date DESC',
    );

    if (results.isEmpty) return 0;

    int streak = 0;
    DateTime? previousDate;

    for (final row in results) {
      final dateStr = row['date'] as String;
      final currentDate = DateTime.parse(dateStr);

      if (previousDate == null) {
        // First row - check if it's today or yesterday
        final today = DateTime.now();
        final yesterday = today.subtract(const Duration(days: 1));
        
        if (_isSameDay(currentDate, today) || _isSameDay(currentDate, yesterday)) {
          streak = 1;
          previousDate = currentDate;
        } else {
          // Last activity was too long ago, streak is broken
          break;
        }
      } else {
        // Check if this date is consecutive with previous
        final daysBetween = previousDate.difference(currentDate).inDays;
        
        if (daysBetween == 1) {
          streak++;
          previousDate = currentDate;
        } else {
          // Gap found, stop counting
          break;
        }
      }
    }

    return streak;
  }

  /// Mark today as completed for user
  /// This is called when user completes a lesson or reaches daily goal
  Future<void> markTodayCompleted(String userId) async {
    final db = await _dbHelper.database;
    final today = _formatDate(DateTime.now());

    await db.insert(
      'streaks',
      {
        'userId': userId,
        'date': today,
        'completed': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Check if user completed activity today
  Future<bool> hasCompletedToday(String userId) async {
    final db = await _dbHelper.database;
    final today = _formatDate(DateTime.now());

    final results = await db.query(
      'streaks',
      where: 'userId = ? AND date = ? AND completed = 1',
      whereArgs: [userId, today],
    );

    return results.isNotEmpty;
  }

  /// Get streak history for visualization (last 7 days)
  Future<List<bool>> getWeekProgress(String userId) async {
    final db = await _dbHelper.database;
    final weekDates = List.generate(7, (index) {
      final date = DateTime.now().subtract(Duration(days: 6 - index));
      return _formatDate(date);
    });

    final progress = <bool>[];
    
    for (final dateStr in weekDates) {
      final results = await db.query(
        'streaks',
        where: 'userId = ? AND date = ? AND completed = 1',
        whereArgs: [userId, dateStr],
      );
      progress.add(results.isNotEmpty);
    }

    return progress;
  }

  /// Get longest streak ever for user
  Future<int> getLongestStreak(String userId) async {
    final db = await _dbHelper.database;
    
    final results = await db.query(
      'streaks',
      where: 'userId = ? AND completed = 1',
      whereArgs: [userId],
      orderBy: 'date ASC',
    );

    if (results.isEmpty) return 0;

    int currentStreak = 1;
    int longestStreak = 1;
    DateTime? previousDate;

    for (final row in results) {
      final dateStr = row['date'] as String;
      final currentDate = DateTime.parse(dateStr);

      if (previousDate != null) {
        final daysBetween = currentDate.difference(previousDate).inDays;
        
        if (daysBetween == 1) {
          currentStreak++;
          if (currentStreak > longestStreak) {
            longestStreak = currentStreak;
          }
        } else if (daysBetween > 1) {
          currentStreak = 1;
        }
      }

      previousDate = currentDate;
    }

    return longestStreak;
  }

  /// Reset streak if user missed yesterday
  /// This is called on app startup to check streak validity
  Future<void> checkAndResetStreakIfNeeded(String userId) async {
    final completed = await hasCompletedToday(userId);
    if (completed) return; // Already active today

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayStr = _formatDate(yesterday);

    final db = await _dbHelper.database;
    final results = await db.query(
      'streaks',
      where: 'userId = ? AND date = ? AND completed = 1',
      whereArgs: [userId, yesterdayStr],
    );

    if (results.isEmpty) {
      // User missed yesterday, streak is broken but data remains
      print('User missed yesterday, streak continues from 0');
    }
  }

  /// Get total active days (lifetime)
  Future<int> getTotalActiveDays(String userId) async {
    final db = await _dbHelper.database;
    
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM streaks WHERE userId = ? AND completed = 1',
      [userId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Helper methods
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}
