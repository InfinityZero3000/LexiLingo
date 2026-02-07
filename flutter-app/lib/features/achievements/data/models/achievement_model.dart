/// Achievement Model - Data layer
/// Maps API responses to domain entities

import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';

class AchievementModel extends AchievementEntity {
  const AchievementModel({
    required super.id,
    super.slug,
    required super.name,
    required super.description,
    required super.conditionType,
    required super.conditionValue,
    super.badgeIcon,
    super.badgeColor,
    required super.category,
    required super.xpReward,
    required super.gemsReward,
    required super.rarity,
    super.isHidden,
  });

  factory AchievementModel.fromJson(Map<String, dynamic> json) {
    return AchievementModel(
      id: json['id']?.toString() ?? '',
      slug: json['slug']?.toString(),
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      conditionType: json['condition_type'] ?? '',
      conditionValue: json['condition_value'] ?? 0,
      badgeIcon: json['badge_icon'],
      badgeColor: json['badge_color'],
      category: json['category'] ?? 'other',
      xpReward: json['xp_reward'] ?? 0,
      gemsReward: json['gems_reward'] ?? 0,
      rarity: json['rarity'] ?? 'common',
      isHidden: json['is_hidden'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'slug': slug,
      'name': name,
      'description': description,
      'condition_type': conditionType,
      'condition_value': conditionValue,
      'badge_icon': badgeIcon,
      'badge_color': badgeColor,
      'category': category,
      'xp_reward': xpReward,
      'gems_reward': gemsReward,
      'rarity': rarity,
      'is_hidden': isHidden,
    };
  }
}

class UserAchievementModel extends UserAchievementEntity {
  const UserAchievementModel({
    required super.id,
    required super.achievement,
    required super.unlockedAt,
    required super.progress,
    super.isShowcased,
  });

  factory UserAchievementModel.fromJson(Map<String, dynamic> json) {
    return UserAchievementModel(
      id: json['id']?.toString() ?? '',
      achievement: AchievementModel.fromJson(json['achievement'] ?? {}),
      unlockedAt: DateTime.tryParse(json['unlocked_at'] ?? '') ?? DateTime.now(),
      progress: json['progress'] ?? 0,
      isShowcased: json['is_showcased'] ?? false,
    );
  }
}

/// Represents a newly unlocked achievement (from API response)
class UnlockedAchievementModel {
  final String id;
  final String name;
  final String description;
  final String? badgeIcon;
  final String? badgeColor;
  final String category;
  final String rarity;
  final int xpReward;
  final int gemsReward;

  const UnlockedAchievementModel({
    required this.id,
    required this.name,
    required this.description,
    this.badgeIcon,
    this.badgeColor,
    required this.category,
    required this.rarity,
    required this.xpReward,
    required this.gemsReward,
  });

  factory UnlockedAchievementModel.fromJson(Map<String, dynamic> json) {
    return UnlockedAchievementModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      badgeIcon: json['badge_icon'],
      badgeColor: json['badge_color'],
      category: json['category'] ?? 'other',
      rarity: json['rarity'] ?? 'common',
      xpReward: json['xp_reward'] ?? 0,
      gemsReward: json['gems_reward'] ?? 0,
    );
  }

  /// Convert to AchievementEntity for display
  AchievementEntity toEntity() {
    return AchievementEntity(
      id: id,
      name: name,
      description: description,
      conditionType: '',
      conditionValue: 0,
      badgeIcon: badgeIcon,
      badgeColor: badgeColor,
      category: category,
      xpReward: xpReward,
      gemsReward: gemsReward,
      rarity: rarity,
    );
  }
}
