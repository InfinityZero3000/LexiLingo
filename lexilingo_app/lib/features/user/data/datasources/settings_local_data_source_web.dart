import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_local_data_source.dart';
import '../models/settings_model.dart';

/// Web implementation of SettingsLocalDataSource using SharedPreferences
class SettingsLocalDataSourceWeb implements SettingsLocalDataSource {
  final SharedPreferences sharedPreferences;
  
  static const String _settingsKey = 'user_settings_';
  
  SettingsLocalDataSourceWeb({required this.sharedPreferences});

  @override
  Future<SettingsModel?> getSettings(String userId) async {
    final jsonString = sharedPreferences.getString('$_settingsKey$userId');
    if (jsonString != null) {
      return SettingsModel.fromJson(json.decode(jsonString));
    }
    return null;
  }

  @override
  Future<int> createSettings(SettingsModel settings) async {
    await sharedPreferences.setString(
      '$_settingsKey${settings.userId}',
      json.encode(settings.toJson()),
    );
    return 1; // Success
  }

  @override
  Future<int> updateSettings(SettingsModel settings) async {
    await sharedPreferences.setString(
      '$_settingsKey${settings.userId}',
      json.encode(settings.toJson()),
    );
    return 1; // Success
  }

  @override
  Future<int> updateNotificationTime(String userId, String time) async {
    final settings = await getSettings(userId);
    if (settings == null) return 0;
    
    // Update the notification time field
    final updatedSettings = SettingsModel(
      id: settings.id,
      userId: settings.userId,
      notificationEnabled: settings.notificationEnabled,
      notificationTime: time,
      soundEnabled: settings.soundEnabled,
      theme: settings.theme,
      language: settings.language,
      dailyGoalXP: settings.dailyGoalXP,
    );
    
    return await updateSettings(updatedSettings);
  }

  @override
  Future<int> updateDailyGoalXP(String userId, int xp) async {
    final settings = await getSettings(userId);
    if (settings == null) return 0;
    
    // Update the daily goal XP field
    final updatedSettings = SettingsModel(
      id: settings.id,
      userId: settings.userId,
      notificationEnabled: settings.notificationEnabled,
      notificationTime: settings.notificationTime,
      soundEnabled: settings.soundEnabled,
      theme: settings.theme,
      language: settings.language,
      dailyGoalXP: xp,
    );
    
    return await updateSettings(updatedSettings);
  }
}
