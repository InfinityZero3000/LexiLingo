import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
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
          const SizedBox(height: AppSpacing.xs),
          rank == 'master'
              ? ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: AppColors.masterGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  child: Text(
                    rankDisplayNameFor(rank),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.surfaceLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : Text(
                  rankDisplayNameFor(rank),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: data.color,
                    fontWeight: FontWeight.bold,
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              data.color.withValues(alpha: 0.15),
              data.color.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: data.color.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Rank Icon
            RankAssetIcon(rank: rank, size: 56),
            const SizedBox(width: AppSpacing.lg),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  rank == 'master'
                      ? ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: AppColors.masterGradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ).createShader(bounds),
                          child: Text(
                            rankDisplayNameFor(rank),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.surfaceLight,
                                ),
                          ),
                        )
                      : Text(
                          rankDisplayNameFor(rank),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: data.color,
                              ),
                        ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'gamification.levelProficiency'.tr(
                      namedArgs: {
                        'level': '$numericLevel',
                        'proficiency': proficiencyLevel,
                      },
                    ),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: data.color,
                  ),
                ),
                Text(
                  'gamification.score'.tr(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
