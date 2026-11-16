/// Achievement Entity - Domain layer
/// Represents an achievement/badge that users can unlock
library;

import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/l10n/relative_time.dart';

class AchievementEntity {
  final String id;
  final String? slug; // Stable identifier for badge asset mapping
  final String name;
  final String description;
  final String conditionType;
  final int conditionValue;
  final String? badgeIcon;
  final String? badgeColor;
  final String category;
  final int xpReward;
  final int gemsReward;
  final String rarity;
  final bool isHidden;

  const AchievementEntity({
    required this.id,
    this.slug,
    required this.name,
    required this.description,
    required this.conditionType,
    required this.conditionValue,
    this.badgeIcon,
    this.badgeColor,
    required this.category,
    required this.xpReward,
    required this.gemsReward,
    required this.rarity,
    this.isHidden = false,
  });

  /// Get rarity color
  int get rarityColorValue {
    switch (rarity) {
      case 'common':
        return 0xFF9E9E9E; // Grey
      case 'rare':
        return 0xFF2196F3; // Blue
      case 'epic':
        return 0xFF9C27B0; // Purple
      case 'legendary':
        return 0xFFFFD700; // Gold
      default:
        return 0xFF9E9E9E;
    }
  }

  /// Get rarity display name
  String get rarityDisplayName {
    switch (rarity) {
      case 'common':
        return 'achievements.rarityCommon'.tr();
      case 'rare':
        return 'achievements.rarityRare'.tr();
      case 'epic':
        return 'achievements.rarityEpic'.tr();
      case 'legendary':
        return 'achievements.rarityLegendary'.tr();
      default:
        return rarity;
    }
  }

  /// Get category display name
  String get categoryDisplayName {
    switch (category) {
      case 'lessons':
        return 'Lessons';
      case 'streak':
        return 'Streak';
      case 'vocabulary':
        return 'Vocabulary';
      case 'quiz':
        return 'Quiz';
      case 'course':
        return 'Courses';
      case 'voice':
        return 'Voice';
      case 'level':
        return 'Level Milestones';
      case 'special':
        return 'Special';
      case 'skill':
        return 'Skill Mastery';
      case 'social':
        return 'Social';
      case 'milestone':
        return 'Milestones';
      default:
        return category;
    }
  }
}

/// User Achievement - represents an unlocked achievement
class UserAchievementEntity {
  final String id;
  final AchievementEntity achievement;
  final DateTime unlockedAt;
  final int progress;
  final bool isShowcased;

  const UserAchievementEntity({
    required this.id,
    required this.achievement,
    required this.unlockedAt,
    required this.progress,
    this.isShowcased = false,
  });

  /// Human readable time since unlock
  String get unlockedTimeAgo => relativeTime(unlockedAt, coarse: true);
}

/// Achievement Progress - for tracking progress towards locked achievements
class AchievementProgressEntity {
  final AchievementEntity achievement;
  final int currentProgress;
  final bool isUnlocked;

  const AchievementProgressEntity({
    required this.achievement,
    required this.currentProgress,
    required this.isUnlocked,
  });

  /// Progress percentage (0-100)
  double get progressPercentage {
    if (isUnlocked) return 100.0;
    if (achievement.conditionValue == 0) return 0.0;
    return (currentProgress / achievement.conditionValue * 100).clamp(
      0.0,
      100.0,
    );
  }

  /// Remaining count to unlock
  int get remaining {
    if (isUnlocked) return 0;
    return (achievement.conditionValue - currentProgress).clamp(
      0,
      achievement.conditionValue,
    );
  }
}
