import 'package:equatable/equatable.dart';

/// Level tier definition
/// Represents a single level tier in the language learning progression
class LevelTier extends Equatable {
  /// Level code (A1, A2, B1, B2, C1, C2)
  final String code;

  /// Human-readable name
  final String name;

  /// Minimum XP required to reach this level
  final int minXP;

  /// Maximum XP for this level (null for max level)
  final int? maxXP;

  /// Color hex code for UI display
  final String colorHex;

  /// Icon identifier for this level
  final String iconIdentifier;

  const LevelTier({
    required this.code,
    required this.name,
    required this.minXP,
    this.maxXP,
    required this.colorHex,
    required this.iconIdentifier,
  });

  /// Check if this is the maximum level
  bool get isMaxLevel => maxXP == null;

  /// Get the XP range for this level
  int get xpRange => isMaxLevel ? 0 : (maxXP! - minXP + 1);

  @override
  List<Object?> get props => [code, name, minXP, maxXP, colorHex, iconIdentifier];
}

/// User's current level status
/// Contains calculated level information based on user's total XP
class LevelStatus extends Equatable {
  /// Current level tier
  final LevelTier currentTier;

  /// Total XP the user has earned
  final int totalXP;

  /// XP earned within current level
  final int xpInCurrentLevel;

  /// XP needed to reach next level (0 if max level)
  final int xpToNextLevel;

  /// Progress percentage within current level (0.0 - 1.0)
  final double progressPercentage;

  /// Next level tier (null if at max level)
  final LevelTier? nextTier;

  const LevelStatus({
    required this.currentTier,
    required this.totalXP,
    required this.xpInCurrentLevel,
    required this.xpToNextLevel,
    required this.progressPercentage,
    this.nextTier,
  });

  /// Check if user is at maximum level
  bool get isAtMaxLevel => nextTier == null;

  /// Get display string for level (e.g., "B2 Upper Intermediate")
  String get displayName => '${currentTier.code} ${currentTier.name}';

  /// Get short display (e.g., "B2")
  String get shortName => currentTier.code;

  /// Factory for empty/default level status
  factory LevelStatus.empty() {
    return LevelStatus(
      currentTier: LevelTiers.a1,
      totalXP: 0,
      xpInCurrentLevel: 0,
      xpToNextLevel: LevelTiers.a1.maxXP! + 1,
      progressPercentage: 0.0,
      nextTier: LevelTiers.a2,
    );
  }

  @override
  List<Object?> get props => [
        currentTier,
        totalXP,
        xpInCurrentLevel,
        xpToNextLevel,
        progressPercentage,
        nextTier,
      ];
}

/// Predefined level tiers following CEFR standard
/// Common European Framework of Reference for Languages
class LevelTiers {
  LevelTiers._();

  static const LevelTier a1 = LevelTier(
    code: 'A1',
    name: 'Beginner',
    minXP: 0,
    maxXP: 999,
    colorHex: '#8BC34A', // Light Green
    iconIdentifier: 'seedling',
  );

  static const LevelTier a2 = LevelTier(
    code: 'A2',
    name: 'Elementary',
    minXP: 1000,
    maxXP: 2999,
    colorHex: '#4CAF50', // Green
    iconIdentifier: 'sprout',
  );

  static const LevelTier b1 = LevelTier(
    code: 'B1',
    name: 'Intermediate',
    minXP: 3000,
    maxXP: 6999,
    colorHex: '#2196F3', // Blue
    iconIdentifier: 'tree',
  );

  static const LevelTier b2 = LevelTier(
    code: 'B2',
    name: 'Upper Intermediate',
    minXP: 7000,
    maxXP: 14999,
    colorHex: '#9C27B0', // Purple
    iconIdentifier: 'forest',
  );

  static const LevelTier c1 = LevelTier(
    code: 'C1',
    name: 'Advanced',
    minXP: 15000,
    maxXP: 29999,
    colorHex: '#FF9800', // Orange
    iconIdentifier: 'star',
  );

  static const LevelTier c2 = LevelTier(
    code: 'C2',
    name: 'Mastery',
    minXP: 30000,
    maxXP: null, // No upper limit
    colorHex: '#FFD700', // Gold
    iconIdentifier: 'crown',
  );

  /// All tiers in order from lowest to highest
  static const List<LevelTier> allTiers = [a1, a2, b1, b2, c1, c2];

  /// Get tier by code
  static LevelTier? getByCode(String code) {
    try {
      return allTiers.firstWhere(
        (tier) => tier.code.toUpperCase() == code.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }
}
