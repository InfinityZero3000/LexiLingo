/// Only a brand-new learner is locked: no completed lesson and no XP earned
/// anywhere. Someone who earned XP from news, podcasts or games keeps every tile.
bool secondaryFeaturesLocked({
  required bool flagEnabled,
  required int? lessonsCompleted,
  required int? totalXp,
}) => flagEnabled && lessonsCompleted == 0 && totalXp == 0;
