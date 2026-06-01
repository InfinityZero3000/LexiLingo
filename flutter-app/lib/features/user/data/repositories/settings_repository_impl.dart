import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import '../../domain/entities/settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';
import '../datasources/settings_remote_data_source.dart';
import '../models/settings_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource localDataSource;
  final SettingsRemoteDataSource? remoteDataSource;

  SettingsRepositoryImpl({
    required this.localDataSource,
    this.remoteDataSource,
  });

  @override
  Future<Either<Failure, Settings>> getSettings(String userId) async {
    try {
      final cachedSettings = await localDataSource.getSettings(userId);
      SettingsModel settings;
      if (cachedSettings == null) {
        settings = SettingsModel(id: 0, userId: userId);
        await localDataSource.createSettings(settings);
      } else {
        settings = cachedSettings;
      }

      if (remoteDataSource != null) {
        try {
          final remote = await remoteDataSource!.getReminderPreferences(userId);
          final merged = SettingsModel.fromEntity(
            settings.copyWith(
              notificationEnabled: remote.notificationEnabled,
              notificationTime: remote.notificationTime,
              pushReminderEnabled: remote.pushReminderEnabled,
              emailReminderEnabled: remote.emailReminderEnabled,
              emailCadenceDays: remote.emailCadenceDays,
              reminderMinDueCount: remote.reminderMinDueCount,
              reminderTimezone: remote.reminderTimezone,
            ),
          );
          await localDataSource.updateSettings(merged);
          settings = merged;
        } catch (_) {
          // Backend reminder sync is best-effort; local settings remain usable.
        }
      }

      return Right(settings);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> createSettings(Settings settings) async {
    try {
      final settingsModel = SettingsModel.fromEntity(settings);
      await localDataSource.createSettings(settingsModel);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateSettings(Settings settings) async {
    try {
      final settingsModel = SettingsModel.fromEntity(settings);
      await localDataSource.updateSettings(settingsModel);
      if (remoteDataSource != null) {
        try {
          await remoteDataSource!.updateReminderPreferences(settings);
        } catch (_) {
          // Keep offline/local-first settings behavior.
        }
      }
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateNotificationTime(
    String userId,
    String time,
  ) async {
    try {
      await localDataSource.updateNotificationTime(userId, time);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateDailyGoalXP(String userId, int xp) async {
    try {
      await localDataSource.updateDailyGoalXP(userId, xp);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }
}
