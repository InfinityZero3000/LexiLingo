import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import '../entities/settings.dart';

abstract class SettingsRepository {
  Future<Either<Failure, Settings>> getSettings(String userId);
  Future<Either<Failure, void>> createSettings(Settings settings);
  Future<Either<Failure, void>> updateSettings(Settings settings);
  Future<Either<Failure, void>> updateNotificationTime(String userId, String time);
  Future<Either<Failure, void>> updateDailyGoalXP(String userId, int xp);
}

