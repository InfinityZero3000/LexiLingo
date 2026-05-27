import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_entity.dart';
import 'package:lexilingo_app/features/level/services/level_calculator.dart';

/// Icon for a CEFR level code (A1–C2)
IconData _cefrIcon(String cefrCode) {
  switch (cefrCode) {
    case 'A1':
      return Icons.eco_outlined;
    case 'A2':
      return Icons.spa_outlined;
    case 'B1':
      return Icons.bolt_outlined;
    case 'B2':
      return Icons.rocket_launch_outlined;
    case 'C1':
      return Icons.workspace_premium_outlined;
    case 'C2':
      return Icons.diamond_outlined;
    default:
      return Icons.school_outlined;
  }
}

/// Color for a CEFR level code (A1–C2)
Color _cefrColor(String cefrCode, bool isDark) {
  switch (cefrCode) {
    case 'A1':
      return AppColors.greenSuccessBright;
    case 'A2':
      return AppColors.teal;
    case 'B1':
      return AppColorRoles.primary(isDark);
    case 'B2':
      return AppColorRoles.primaryDeep(isDark);
    case 'C1':
      return AppColors.purple;
    case 'C2':
      return AppColors.warning;
    default:
      return AppColorRoles.primary(isDark);
  }
}

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
            colors: [tierColor, tierColor.withValues(alpha: 0.8)],
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

  const LevelProgressCard({super.key, this.onTap, this.compact = false});

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
          onTap: onTap ?? () => _showLevelDetails(context),
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
                              'profile.level'.tr(
                                namedArgs: {'level': '$level'},
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: titleFontSize,
                                  ),
                            ),
                            Text(
                              'profile.xpProgress'.tr(
                                namedArgs: {
                                  'current': '$xpIn',
                                  'total': '$xpFor',
                                },
                              ),

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
                                'profile.level'.tr(
                                  namedArgs: {'level': '$level'},
                                ),
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: titleFontSize,
                                    ),
                              ),
                              Text(
                                'home.xpThisLevel'.tr(
                                  namedArgs: {
                                    'current': '$xpIn',
                                    'total': '$xpFor',
                                  },
                                ),

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
                            'profile.totalXp'.tr(),
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
                        'profile.percentComplete'.tr(
                          namedArgs: {'percent': '${(progress * 100).toInt()}'},
                        ),

                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                        valueColor: AlwaysStoppedAnimation<Color>(accent),
                        minHeight: progressHeight,
                      ),
                    ),
                    SizedBox(height: compact ? 3 : 4),
                    Text(
                      'profile.xpToNextLevel'.tr(
                        namedArgs: {
                          'xp': '${xpFor - xpIn}',
                          'level': '${level + 1}',
                        },
                      ),

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

  void _showLevelDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const LevelDetailsSheet(),
    );
  }
}

/// Level details bottom sheet — shows CEFR Proficiency and Activity Level separately.
class LevelDetailsSheet extends StatelessWidget {
  const LevelDetailsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LevelProvider>(
      builder: (context, lp, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final accent = AppColorRoles.primary(isDark);
        final cefrColor = _cefrColor(lp.proficiencyLevel, isDark);

        return Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppColors.grey300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── Section 1: CEFR Proficiency ──
                _SectionHeader(
                  icon: Icons.school_rounded,
                  title: 'home.englishProficiency'.tr(),
                  subtitle: 'home.proficiencySubtitle'.tr(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cefrColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cefrColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cefrColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _cefrIcon(lp.proficiencyLevel),
                          size: 28,
                          color: cefrColor,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lp.proficiencyLevel,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cefrColor,
                                ),
                          ),
                          Text(
                            lp.proficiencyName,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Divider(color: Colors.grey.withValues(alpha: 0.2)),
                const SizedBox(height: 20),

                // ── Section 2: Activity Level ──
                _SectionHeader(
                  icon: Icons.workspace_premium_rounded,
                  title: 'home.activityLevel'.tr(),
                  subtitle: 'home.activityLevelSubtitle'.tr(),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'profile.level'.tr(
                              namedArgs: {'level': '${lp.displayLevel}'},
                            ),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'home.xpTotal'.tr(
                              namedArgs: {
                                'xp': LevelCalculator.formatXP(lp.totalXp),
                              },
                            ),

                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: lp.displayLevelProgress,
                          backgroundColor: AppColors.grey200,
                          valueColor: AlwaysStoppedAnimation<Color>(accent),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${lp.displayXpInLevel} / ${lp.displayXpForNextLevel} XP',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            '${(lp.displayLevelProgress * 100).toInt()}%',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'profile.xpToNextLevel'.tr(
                          namedArgs: {
                            'xp':
                                '${lp.displayXpForNextLevel - lp.displayXpInLevel}',
                            'level': '${lp.displayLevel + 1}',
                          },
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Reusable section header with icon, title, and subtitle.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
