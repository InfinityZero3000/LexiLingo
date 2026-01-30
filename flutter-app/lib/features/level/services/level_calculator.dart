import '../domain/entities/level_entity.dart';

/// Level Calculator Service
/// Provides algorithms for calculating user level based on XP
///
/// Level Thresholds (CEFR-based):
/// - A1 (Beginner): 0 - 999 XP
/// - A2 (Elementary): 1,000 - 2,999 XP
/// - B1 (Intermediate): 3,000 - 6,999 XP
/// - B2 (Upper Intermediate): 7,000 - 14,999 XP
/// - C1 (Advanced): 15,000 - 29,999 XP
/// - C2 (Mastery): 30,000+ XP
class LevelCalculator {
  LevelCalculator._();

  /// Calculate the current level tier based on total XP
  ///
  /// Returns the highest level tier that the user has reached
  /// based on their total XP.
  static LevelTier getCurrentTier(int totalXP) {
    // Ensure non-negative XP
    final xp = totalXP < 0 ? 0 : totalXP;

    // Iterate from highest to lowest tier to find current level
    for (final tier in LevelTiers.allTiers.reversed) {
      if (xp >= tier.minXP) {
        return tier;
      }
    }

    // Default to A1 if somehow no tier matched
    return LevelTiers.a1;
  }

  /// Get the next level tier
  ///
  /// Returns null if user is at maximum level (C2)
  static LevelTier? getNextTier(LevelTier currentTier) {
    final currentIndex = LevelTiers.allTiers.indexOf(currentTier);
    if (currentIndex < 0 || currentIndex >= LevelTiers.allTiers.length - 1) {
      return null; // At max level or tier not found
    }
    return LevelTiers.allTiers[currentIndex + 1];
  }

  /// Calculate XP earned within the current level
  ///
  /// This is the XP above the minimum threshold for the current tier.
  static int getXPInCurrentLevel(int totalXP) {
    final currentTier = getCurrentTier(totalXP);
    return totalXP - currentTier.minXP;
  }

  /// Calculate XP needed to reach the next level
  ///
  /// Returns 0 if user is at maximum level (C2)
  static int getXPToNextLevel(int totalXP) {
    final currentTier = getCurrentTier(totalXP);

    // If at max level, return 0
    if (currentTier.isMaxLevel) {
      return 0;
    }

    // Calculate remaining XP needed
    return currentTier.maxXP! - totalXP + 1;
  }

  /// Calculate progress percentage within current level
  ///
  /// Returns a value between 0.0 and 1.0
  /// Returns 1.0 if user is at maximum level
  static double getProgressPercentage(int totalXP) {
    final currentTier = getCurrentTier(totalXP);

    // If at max level, return 100%
    if (currentTier.isMaxLevel) {
      return 1.0;
    }

    final xpInLevel = getXPInCurrentLevel(totalXP);
    final levelRange = currentTier.xpRange;

    if (levelRange <= 0) {
      return 0.0;
    }

    return (xpInLevel / levelRange).clamp(0.0, 1.0);
  }

  /// Calculate complete level status for a user
  ///
  /// This is the main method that returns all level-related information
  /// in a single LevelStatus object.
  static LevelStatus calculateLevelStatus(int totalXP) {
    final currentTier = getCurrentTier(totalXP);
    final nextTier = getNextTier(currentTier);
    final xpInCurrentLevel = getXPInCurrentLevel(totalXP);
    final xpToNextLevel = getXPToNextLevel(totalXP);
    final progressPercentage = getProgressPercentage(totalXP);

    return LevelStatus(
      currentTier: currentTier,
      totalXP: totalXP,
      xpInCurrentLevel: xpInCurrentLevel,
      xpToNextLevel: xpToNextLevel,
      progressPercentage: progressPercentage,
      nextTier: nextTier,
    );
  }

  /// Check if XP change would result in a level up
  ///
  /// Useful for triggering level up animations/notifications
  static bool wouldLevelUp(int currentXP, int xpToAdd) {
    final currentTier = getCurrentTier(currentXP);
    final newTier = getCurrentTier(currentXP + xpToAdd);
    return newTier.minXP > currentTier.minXP;
  }

  /// Get the number of levels gained from XP addition
  ///
  /// Returns 0 if no level change, or the number of levels gained
  static int getLevelsGained(int currentXP, int xpToAdd) {
    final currentTierIndex = LevelTiers.allTiers.indexOf(getCurrentTier(currentXP));
    final newTierIndex = LevelTiers.allTiers.indexOf(getCurrentTier(currentXP + xpToAdd));
    return (newTierIndex - currentTierIndex).clamp(0, LevelTiers.allTiers.length);
  }

  /// Get XP required to reach a specific level from current XP
  ///
  /// Returns 0 if already at or above the target level
  static int getXPRequiredForLevel(int currentXP, LevelTier targetTier) {
    if (currentXP >= targetTier.minXP) {
      return 0;
    }
    return targetTier.minXP - currentXP;
  }

  /// Format XP for display (e.g., "1,234" or "12.3K")
  static String formatXP(int xp) {
    if (xp >= 1000000) {
      return '${(xp / 1000000).toStringAsFixed(1)}M';
    } else if (xp >= 10000) {
      return '${(xp / 1000).toStringAsFixed(1)}K';
    } else if (xp >= 1000) {
      // Add comma separator
      return xp.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (Match m) => '${m[1]},',
          );
    }
    return xp.toString();
  }

  /// Get a motivational message based on level progress
  static String getMotivationalMessage(LevelStatus status) {
    if (status.isAtMaxLevel) {
      return 'You have achieved mastery! Keep practicing to maintain your skills.';
    }

    final percentage = status.progressPercentage * 100;

    if (percentage < 25) {
      return 'Great start on ${status.currentTier.code}! Keep learning every day.';
    } else if (percentage < 50) {
      return 'Making good progress! You are ${percentage.toStringAsFixed(0)}% through ${status.currentTier.code}.';
    } else if (percentage < 75) {
      return 'Over halfway to ${status.nextTier?.code ?? 'next level'}! Keep going!';
    } else {
      return 'Almost there! Just ${status.xpToNextLevel} XP to ${status.nextTier?.code ?? 'next level'}!';
    }
  }
}
