import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_badge.dart';

/// Combined Level + Rank display widget for profile / home page.
///
/// Shows:
/// - Numeric level with XP progress bar
/// - CEFR proficiency tag
/// - Rank badge with score
class LevelRankDisplay extends StatelessWidget {
  final int numericLevel;
  final int currentXpInLevel;
  final int xpForNextLevel;
  final double levelProgressPercent;
  final int totalXp;
  final String proficiencyLevel;
  final String proficiencyName;
  final String rank;
  final String rankName;
  final double rankScore;
  final VoidCallback? onTap;

  const LevelRankDisplay({
    super.key,
    required this.numericLevel,
    required this.currentXpInLevel,
    required this.xpForNextLevel,
    required this.levelProgressPercent,
    required this.totalXp,
    required this.proficiencyLevel,
    required this.proficiencyName,
    required this.rank,
    required this.rankName,
    required this.rankScore,
    this.onTap,
  });

  /// Build from API JSON map (e.g. /me/level-full response)
  factory LevelRankDisplay.fromJson(Map<String, dynamic> json,
      {VoidCallback? onTap}) {
    return LevelRankDisplay(
      numericLevel: json['numeric_level'] ?? 1,
      currentXpInLevel: json['current_xp_in_level'] ?? 0,
      xpForNextLevel: json['xp_for_next_level'] ?? 100,
      levelProgressPercent:
          (json['level_progress_percent'] ?? 0).toDouble(),
      totalXp: json['total_xp'] ?? 0,
      proficiencyLevel: json['proficiency_level'] ?? 'A1',
      proficiencyName: json['proficiency_name'] ?? 'Beginner',
      rank: json['rank'] ?? 'bronze',
      rankName: json['rank_name'] ?? 'Bronze',
      rankScore: (json['rank_score'] ?? 0).toDouble(),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = (levelProgressPercent / 100).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Level number + CEFR tag + Rank badge
            Row(
              children: [
                // Level number
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Lv.$numericLevel',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // CEFR proficiency tag
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _proficiencyColor(proficiencyLevel)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _proficiencyColor(proficiencyLevel)
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '$proficiencyLevel · $proficiencyName',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _proficiencyColor(proficiencyLevel),
                    ),
                  ),
                ),
                const Spacer(),
                // Rank badge
                RankBadge(rank: rank, size: 32),
              ],
            ),
            const SizedBox(height: 12),
            // XP progress bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor:
                          colorScheme.surfaceContainerHighest,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_formatNumber(currentXpInLevel)} / ${_formatNumber(xpForNextLevel)} XP',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Bottom: Total XP + Rank name & score
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total: ${_formatNumber(totalXp)} XP',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  '$rankName · Score ${rankScore.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Color _proficiencyColor(String level) {
    switch (level.toUpperCase()) {
      case 'A1':
        return const Color(0xFF4CAF50);
      case 'A2':
        return const Color(0xFF8BC34A);
      case 'B1':
        return const Color(0xFF2196F3);
      case 'B2':
        return const Color(0xFF3F51B5);
      case 'C1':
        return const Color(0xFF9C27B0);
      case 'C2':
        return const Color(0xFFFF9800);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  static String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return n.toString();
  }
}
