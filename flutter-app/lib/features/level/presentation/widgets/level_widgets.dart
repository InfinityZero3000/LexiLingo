import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_entity.dart';
import 'package:lexilingo_app/features/level/services/level_calculator.dart';

/// Icon mapping for tier identifiers - returns IconData for Material icons
IconData _getTierIcon(String iconIdentifier) {
  switch (iconIdentifier) {
    case 'seedling':
      return Icons.eco_outlined;
    case 'sprout':
      return Icons.grass;
    case 'tree':
      return Icons.park;
    case 'forest':
      return Icons.forest;
    case 'star':
      return Icons.star;
    case 'crown':
      return Icons.workspace_premium;
    default:
      return Icons.school;
  }
}

/// Color mapping for tiers
Color _getTierColor(LevelTier tier) {
  final hex = tier.colorHex.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

/// Compact level badge for header display
class LevelBadge extends StatelessWidget {
  final String tierCode;
  final LevelTier tier;
  final double progress;
  final VoidCallback? onTap;

  const LevelBadge({
    super.key,
    required this.tierCode,
    required this.tier,
    required this.progress,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tierColor = _getTierColor(tier);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              tierColor,
              tierColor.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: tierColor.withValues(alpha: 0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getTierIcon(tier.iconIdentifier),
              size: 16,
              color: Theme.of(context).colorScheme.surface,
            ),
            const SizedBox(width: 4),
            Text(
              tierCode,
              style: TextStyle(
                color: Theme.of(context).colorScheme.surface,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full level progress card for home page
class LevelProgressCard extends StatelessWidget {
  final VoidCallback? onTap;
  final bool compact;

  const LevelProgressCard({
    super.key,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<LevelProvider>(
      builder: (context, levelProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accent = AppColorRoles.primary(isDark);
        final level = levelProvider.displayLevel;
        final xpIn = levelProvider.displayXpInLevel;
        final xpFor = levelProvider.displayXpForNextLevel;
        final progress = levelProvider.displayLevelProgress;
        final totalXp = levelProvider.levelStatus.totalXP;
        final cardPadding = compact ? 12.0 : 16.0;
        final iconPadding = compact ? 6.0 : 8.0;
        final iconSize = compact ? 20.0 : 24.0;
        final titleFontSize = compact ? 17.0 : null;
        final xpLineFontSize = compact ? 11.0 : null;
        final totalXpFontSize = compact ? 16.0 : null;
        final sectionGap = compact ? 8.0 : 12.0;
        final progressGap = compact ? 6.0 : 8.0;
        final progressHeight = compact ? 6.0 : 8.0;
        final toNextFontSize = compact ? 10.0 : 11.0;

        return GestureDetector(
          onTap:
              onTap ??
              () => _showLevelDetails(context, levelProvider.levelStatus),
          child: Container(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact)
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(iconPadding),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.workspace_premium_rounded,
                          size: iconSize,
                          color: accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Level $level',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: titleFontSize,
                                  ),
                            ),
                            Text(
                              '$xpIn / $xpFor XP',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AppColors.textGrey,
                                    fontSize: xpLineFontSize,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(iconPadding),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              size: iconSize,
                              color: accent,
                            ),
                          ),
                          SizedBox(width: compact ? 8 : 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Level $level',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: titleFontSize,
                                    ),
                              ),
                              Text(
                                '$xpIn / $xpFor XP this level',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppColors.textGrey,
                                      fontSize: xpLineFontSize,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            LevelCalculator.formatXP(totalXp),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: accent,
                                  fontSize: totalXpFontSize,
                                ),
                          ),
                          Text(
                            'Total XP',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.textGrey),
                          ),
                        ],
                      ),
                    ],
                  ),
                SizedBox(height: sectionGap),
                // Progress bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${(progress * 100).toInt()}% complete',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                              fontSize: compact ? 10.5 : null,
                            ),
                      ),
                    ),
                    SizedBox(height: progressGap),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: AppColors.grey200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          accent,
                        ),
                        minHeight: progressHeight,
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 4),
                    Text(
                      '${xpFor - xpIn} XP to Level ${level + 1}',
                      maxLines: compact ? 1 : null,
                      overflow: compact ? TextOverflow.ellipsis : null,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textGrey,
                        fontSize: toNextFontSize,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showLevelDetails(BuildContext context, LevelStatus status) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LevelDetailsSheet(status: status),
    );
  }
}

/// Level details bottom sheet
class LevelDetailsSheet extends StatelessWidget {
  final LevelStatus status;

  const LevelDetailsSheet({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final currentTierColor = _getTierColor(status.currentTier);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Level icon
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: currentTierColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _getTierIcon(status.currentTier.iconIdentifier),
              size: 48,
              color: currentTierColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            status.currentTier.code,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            status.currentTier.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: currentTierColor,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          // XP Stats
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  context,
                  LevelCalculator.formatXP(status.totalXP),
                  'Total XP',
                ),
                Container(width: 1, height: 40, color: AppColors.grey200),
                _buildStatItem(
                  context,
                  '${status.xpInCurrentLevel}',
                  'Current Level',
                ),
                Container(width: 1, height: 40, color: AppColors.grey200),
                _buildStatItem(context, '${status.xpToNextLevel}', 'To Next'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // All tiers
          Text(
            'Level Tiers',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...LevelTiers.allTiers.map(
            (tier) => _buildTierRow(
              context,
              tier,
              tier.code == status.currentTier.code,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColors.textGrey,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  Widget _buildTierRow(BuildContext context, LevelTier tier, bool isCurrent) {
    final tierColor = _getTierColor(tier);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isCurrent
            ? tierColor.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isCurrent ? Border.all(color: tierColor) : null,
      ),
      child: Row(
        children: [
          Icon(
            _getTierIcon(tier.iconIdentifier),
            size: 20,
            color: tierColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tier.code} - ${tier.name}',
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? tierColor : null,
                  ),
                ),
                Text(
                  '${LevelCalculator.formatXP(tier.minXP)} - ${tier.maxXP != null ? LevelCalculator.formatXP(tier.maxXP!) : "Max"} XP',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textGrey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (isCurrent) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, color: AppColors.greenSuccessBright, size: 20),
          ],
        ],
      ),
    );
  }
}
