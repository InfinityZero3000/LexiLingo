import '../../domain/entities/daily_challenge_entity.dart';

/// Daily Challenge Model
/// Data layer model for API communication
class DailyChallengeModel extends DailyChallengeEntity {
  const DailyChallengeModel({
    required super.id,
    required super.title,
    required super.description,
    required super.icon,
    required super.category,
    required super.target,
    required super.current,
    required super.xpReward,
    required super.isCompleted,
    required super.expiresAt,
  });

  factory DailyChallengeModel.fromJson(Map<String, dynamic> json) {
    return DailyChallengeModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      icon: json['icon'] ?? '🎯',
      category: json['category'] ?? 'other',
      target: json['target'] ?? 1,
      current: json['current'] ?? 0,
      xpReward: json['xp_reward'] ?? 0,
      isCompleted: json['is_completed'] ?? false,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : DateTime.now().add(const Duration(days: 1)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'icon': icon,
      'category': category,
      'target': target,
      'current': current,
      'xp_reward': xpReward,
      'is_completed': isCompleted,
      'expires_at': expiresAt.toIso8601String(),
    };
  }
}

/// Daily Challenges List Model
class DailyChallengesResponseModel extends DailyChallengesResponse {
  const DailyChallengesResponseModel({
    required super.date,
    required super.challenges,
    required super.totalCompleted,
    required super.totalChallenges,
    required super.bonusXp,
  });

  factory DailyChallengesResponseModel.fromJson(Map<String, dynamic> json) {
    final challengesList = (json['challenges'] as List?)
            ?.map((c) => DailyChallengeModel.fromJson(c))
            .toList() ??
        [];

    return DailyChallengesResponseModel(
      date: json['date'] ?? DateTime.now().toIso8601String().split('T').first,
      challenges: challengesList,
      totalCompleted: json['total_completed'] ?? 0,
      totalChallenges: json['total_challenges'] ?? challengesList.length,
      bonusXp: json['bonus_xp'] ?? 0,
    );
  }
}
