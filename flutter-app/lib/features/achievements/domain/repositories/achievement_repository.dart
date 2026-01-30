/// Achievement Repository Interface - Domain layer

import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';

abstract class AchievementRepository {
  /// Get all available achievements
  Future<List<AchievementEntity>> getAllAchievements();

  /// Get current user's unlocked achievements
  Future<List<UserAchievementEntity>> getMyAchievements();

  /// Force check all achievements
  Future<List<UnlockedAchievementModel>> checkAllAchievements();
}
