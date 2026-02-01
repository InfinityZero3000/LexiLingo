/// Achievement Repository Interface - Domain layer

import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';

abstract class AchievementRepository {
  /// Get all available achievements
  Future<List<AchievementEntity>> getAllAchievements();

  /// Get current user's unlocked achievements
  Future<List<UserAchievementEntity>> getMyAchievements();

  /// Get recently earned badges (sorted by unlocked_at DESC)
  /// Following agent-skills/gamification-achievement-badges pattern:
  /// Display recent badges for engagement boost (25-40%)
  Future<List<UserAchievementEntity>> getRecentBadges({int limit = 4});

  /// Force check all achievements
  Future<List<UnlockedAchievementModel>> checkAllAchievements();
}
