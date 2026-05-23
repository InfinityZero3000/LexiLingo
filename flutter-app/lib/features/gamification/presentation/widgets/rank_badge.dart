import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';

/// Compact rank badge for profile / header display
class RankBadge extends StatelessWidget {
  final String rank;
  final double size;
  final VoidCallback? onTap;

  const RankBadge({super.key, required this.rank, this.size = 36, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: RankAssetIcon(rank: rank, size: size),
    );
  }
}

/// Labelled rank badge with name below the icon
class RankBadgeLabelled extends StatelessWidget {
  final String rank;
  final double iconSize;
  final VoidCallback? onTap;

  const RankBadgeLabelled({
    super.key,
    required this.rank,
    this.iconSize = 48,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = rankVisualDataFor(rank);

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RankBadge(rank: rank, size: iconSize, onTap: null),
          const SizedBox(height: 4),
          Text(
            rankDisplayNameFor(rank),
            style: TextStyle(
              color: data.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full rank card for profile pages
class RankCard extends StatelessWidget {
  final String rank;
  final double rankScore;
  final int numericLevel;
  final String proficiencyLevel;
  final VoidCallback? onTap;

  const RankCard({
    super.key,
    required this.rank,
    required this.rankScore,
    required this.numericLevel,
    required this.proficiencyLevel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = rankVisualDataFor(rank);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              data.color.withValues(alpha: 0.15),
              data.color.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: data.color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Rank Icon
            RankAssetIcon(rank: rank, size: 56),
            const SizedBox(width: 16),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rankDisplayNameFor(rank),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: data.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'gamification.levelProficiency'.tr(
                      namedArgs: {
                        'level': '$numericLevel',
                        'proficiency': proficiencyLevel,
                      },
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            // Score
            Column(
              children: [
                Text(
                  rankScore.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: data.color,
                  ),
                ),
                Text(
                  'gamification.score'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
