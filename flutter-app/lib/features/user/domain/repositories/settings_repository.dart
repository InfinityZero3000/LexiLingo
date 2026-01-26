import '../entities/settings.dart';

abstract class SettingsRepository {
  Future<Settings?> getSettings(String userId);
  Future<void> createSettings(Settings settings);
  Future<void> updateSettings(Settings settings);
  Future<void> updateNotificationTime(String userId, String time);
  Future<void> updateDailyGoalXP(String userId, int xp);
}
