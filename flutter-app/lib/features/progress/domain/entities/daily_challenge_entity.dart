import 'package:equatable/equatable.dart';

/// Daily Challenge Entity
/// Represents a single daily challenge for gamification
class DailyChallengeEntity extends Equatable {
  final String id;
  final String title;
  final String description;
  final String icon;
  final String category; // lesson, vocabulary, streak, xp, voice, social
  final int target;
  final int current;
  final int xpReward;
  final bool isCompleted;
  final DateTime expiresAt;

  const DailyChallengeEntity({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.category,
    required this.target,
    required this.current,
    required this.xpReward,
    required this.isCompleted,
    required this.expiresAt,
  });

  /// Progress percentage (0.0 - 1.0)
  double get progress => target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;

  /// Progress percentage as int (0 - 100)
  int get progressPercent => (progress * 100).toInt();

  /// Remaining count to complete
  int get remaining => (target - current).clamp(0, target);

  /// Whether challenge is in progress
  bool get isInProgress => !isCompleted && current > 0;

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        icon,
        category,
        target,
        current,
        xpReward,
        isCompleted,
        expiresAt,
      ];
}

/// Daily Challenges List Response
class DailyChallengesResponse extends Equatable {
  final String date;
  final List<DailyChallengeEntity> challenges;
  final int totalCompleted;
  final int totalChallenges;
  final int bonusXp;

  const DailyChallengesResponse({
    required this.date,
    required this.challenges,
    required this.totalCompleted,
    required this.totalChallenges,
    required this.bonusXp,
  });

  /// Whether all challenges are completed
  bool get allCompleted => totalCompleted == totalChallenges;

  /// Completion progress (0.0 - 1.0)
  double get progress =>
      totalChallenges > 0 ? totalCompleted / totalChallenges : 0.0;

  /// Total XP available from all challenges
  int get totalXpAvailable =>
      challenges.fold(0, (sum, c) => sum + c.xpReward) + bonusXp;

  /// XP already earned from completed challenges
  int get xpEarned =>
      challenges.where((c) => c.isCompleted).fold(0, (sum, c) => sum + c.xpReward);

  @override
  List<Object?> get props => [
        date,
        challenges,
        totalCompleted,
        totalChallenges,
        bonusXp,
      ];
}
