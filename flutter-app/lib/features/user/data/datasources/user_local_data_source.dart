import 'package:sqflite/sqflite.dart';
import '../models/user_model.dart';
import '../../../../core/services/database_helper.dart';

abstract class UserLocalDataSource {
  Future<UserModel?> getUser(String userId);
  Future<int> createUser(UserModel user);
  Future<int> updateUser(UserModel user);
  Future<int> updateUserStats({
    required String userId,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  });
  Future<int> updateLastLogin(String userId);
}

class UserLocalDataSourceImpl implements UserLocalDataSource {
  final DatabaseHelper databaseHelper;

  UserLocalDataSourceImpl({required this.databaseHelper});

  @override
  Future<UserModel?> getUser(String userId) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    );

    if (maps.isEmpty) {
      return null;
    }

    return UserModel.fromJson(maps.first);
  }

  @override
  Future<int> createUser(UserModel user) async {
    final db = await databaseHelper.database;
    final data = user.toJson();
    
    // For insert, we don't use the id field since it's the primary key
    await db.insert(
      'users',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    
    return 1; // Success
  }

  @override
  Future<int> updateUser(UserModel user) async {
    final db = await databaseHelper.database;
    return await db.update(
      'users',
      user.toJson(),
      where: 'id = ?',
      whereArgs: [user.id],
    );
  }

  @override
  Future<int> updateUserStats({
    required String userId,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  }) async {
    final db = await databaseHelper.database;
    
    final Map<String, dynamic> updates = {};
    if (totalXP != null) updates['totalXP'] = totalXP;
    if (currentStreak != null) updates['currentStreak'] = currentStreak;
    if (longestStreak != null) updates['longestStreak'] = longestStreak;
    if (totalLessonsCompleted != null) updates['totalLessonsCompleted'] = totalLessonsCompleted;
    if (totalWordsLearned != null) updates['totalWordsLearned'] = totalWordsLearned;
    
    if (updates.isEmpty) return 0;
    
    return await db.update(
      'users',
      updates,
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  @override
  Future<int> updateLastLogin(String userId) async {
    final db = await databaseHelper.database;
    return await db.update(
      'users',
      {'lastLoginDate': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [userId],
    );
  }
}
