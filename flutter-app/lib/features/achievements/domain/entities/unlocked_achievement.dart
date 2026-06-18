class UnlockedAchievement {
  final String id;
  final String name;
  final String description;
  final String? badgeIcon;
  final String? badgeColor;
  final String category;
  final String rarity;
  final int xpReward;
  final int gemsReward;

  const UnlockedAchievement({
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
}
