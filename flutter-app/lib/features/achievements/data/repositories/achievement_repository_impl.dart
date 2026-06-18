/// Achievement Repository Implementation - Data layer
library;

import 'package:lexilingo_app/features/achievements/data/datasources/achievement_remote_datasource.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/unlocked_achievement.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';

class AchievementRepositoryImpl implements AchievementRepository {
  final AchievementRemoteDataSource remoteDataSource;

  AchievementRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<AchievementEntity>> getAllAchievements() async {
    return await remoteDataSource.getAllAchievements();
  }

  @override
  Future<List<UserAchievementEntity>> getMyAchievements() async {
    return await remoteDataSource.getMyAchievements();
  }

  @override
  Future<List<UserAchievementEntity>> getRecentBadges({int limit = 4}) async {
    return await remoteDataSource.getRecentBadges(limit: limit);
  }

  @override
  Future<List<UnlockedAchievement>> checkAllAchievements() async {
    return await remoteDataSource.checkAllAchievements();
  }
}
