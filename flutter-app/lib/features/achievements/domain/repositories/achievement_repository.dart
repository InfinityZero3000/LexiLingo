/// Achievement Repository Interface - Domain layer
library;

import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/unlocked_achievement.dart';

abstract class AchievementRepository {
  Future<List<AchievementEntity>> getAllAchievements();

  Future<List<UserAchievementEntity>> getMyAchievements();

  Future<List<UserAchievementEntity>> getRecentBadges({int limit = 4});

  Future<List<UnlockedAchievement>> checkAllAchievements();
}
