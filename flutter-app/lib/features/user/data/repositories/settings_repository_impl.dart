import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import '../../domain/entities/settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_data_source.dart';
import '../models/settings_model.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  final SettingsLocalDataSource localDataSource;

  SettingsRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, Settings>> getSettings(String userId) async {
    try {
      final settings = await localDataSource.getSettings(userId);
      if (settings != null) {
        return Right(settings);
      }
      // Create default settings if not found
      final defaultSettings = SettingsModel(
        id: 0,
        userId: userId,
      );
      await localDataSource.createSettings(defaultSettings);
      return Right(defaultSettings);
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
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> updateNotificationTime(String userId, String time) async {
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
