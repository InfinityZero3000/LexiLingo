import '../../domain/entities/settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';
import '../models/settings_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource localDataSource;

  SettingsRepositoryImpl({required this.localDataSource});

  @override
  Future<Settings?> getSettings(String userId) async {
    return await localDataSource.getSettings(userId);
  }

  @override
  Future<void> createSettings(Settings settings) async {
    final settingsModel = SettingsModel.fromEntity(settings);
    await localDataSource.createSettings(settingsModel);
  }

  @override
  Future<void> updateSettings(Settings settings) async {
    final settingsModel = SettingsModel.fromEntity(settings);
    await localDataSource.updateSettings(settingsModel);
  }

  @override
  Future<void> updateNotificationTime(String userId, String time) async {
    await localDataSource.updateNotificationTime(userId, time);
  }

  @override
  Future<void> updateDailyGoalXP(String userId, int xp) async {
    await localDataSource.updateDailyGoalXP(userId, xp);
  }
}
