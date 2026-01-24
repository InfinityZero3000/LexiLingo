import 'package:sqflite/sqflite.dart';
import '../models/settings_model.dart';
import '../../../../core/services/database_helper.dart';

abstract class SettingsLocalDataSource {
  Future<SettingsModel?> getSettings(String userId);
  Future<int> createSettings(SettingsModel settings);
  Future<int> updateSettings(SettingsModel settings);
  Future<int> updateNotificationTime(String userId, String time);
  Future<int> updateDailyGoalXP(String userId, int xp);
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  final DatabaseHelper databaseHelper;

  SettingsLocalDataSourceImpl({required this.databaseHelper});

  @override
  Future<SettingsModel?> getSettings(String userId) async {
    final db = await databaseHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'settings',
      where: 'userId = ?',
      whereArgs: [userId],
    );

    if (maps.isEmpty) {
      return null;
    }

    return SettingsModel.fromJson(maps.first);
  }

  @override
  Future<int> createSettings(SettingsModel settings) async {
    final db = await databaseHelper.database;
    return await db.insert(
      'settings',
      settings.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<int> updateSettings(SettingsModel settings) async {
    final db = await databaseHelper.database;
    return await db.update(
      'settings',
      settings.toJson(),
      where: 'userId = ?',
      whereArgs: [settings.userId],
    );
  }

  @override
  Future<int> updateNotificationTime(String userId, String time) async {
    final db = await databaseHelper.database;
    return await db.update(
      'settings',
      {'notificationTime': time},
      where: 'userId = ?',
      whereArgs: [userId],
    );
  }

  @override
  Future<int> updateDailyGoalXP(String userId, int xp) async {
    final db = await databaseHelper.database;
    return await db.update(
      'settings',
      {'dailyGoalXP': xp},
      where: 'userId = ?',
      whereArgs: [userId],
    );
  }
}
