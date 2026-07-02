import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_ui_components.dart';
import 'package:lexilingo_app/features/user/domain/entities/weekly_activity_entity.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

void _showWeeklyActivityDetail(
  BuildContext context,
  List<WeeklyActivityEntity> activities,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WeeklyActivityDetailSheet(activities: activities),
  );
}

class WeeklyActivitySection extends StatelessWidget {
  const WeeklyActivitySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final activities = profileProvider.weeklyActivity;
        final isLoading = profileProvider.isLoadingActivity;
        final activityError = profileProvider.activityError;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'profile.weeklyActivity'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  GestureDetector(
                    onTap: activities.isNotEmpty
                        ? () => _showWeeklyActivityDetail(context, activities)
                        : null,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'profile.last7Days'.tr(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (activities.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            GlassmorphicContainer(
              child: isLoading && activities.isEmpty
                  ? SizedBox(
                      width: double.infinity,
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: ShimmerContainer(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 120,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(
                                    7,
                                    (index) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        child: SkeletonBox(
                                          height: 20.0 + (index % 3) * 30.0,
                                          borderRadius: 4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: List.generate(
                                  7,
                                  (index) => const Expanded(
                                    child: Center(
                                      child: SkeletonBox(
                                        width: 20,
                                        height: 12,
                                        borderRadius: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: List.generate(
                                  3,
                                  (index) => const Column(
                                    children: [
                                      SkeletonCircle(size: 20),
                                      SizedBox(height: 4),
                                      SkeletonBox(
                                        width: 40,
                                        height: 16,
                                        borderRadius: 4,
                                      ),
                                      SizedBox(height: 4),
                                      SkeletonBox(
                                        width: 60,
                                        height: 12,
                                        borderRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : activities.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          activityError == null || activityError.isEmpty
                              ? 'profile.noActivityDataYet'.tr()
                              : activityError,
                          style: const TextStyle(color: AppColors.grey600),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        // XP Chart with animated bars
                        SizedBox(
                          height: 120,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: activities.asMap().entries.map((entry) {
                              final index = entry.key;
                              final activity = entry.value;
                              final maxXP = activities
                                  .map((a) => a.xpEarned)
                                  .reduce((a, b) => a > b ? a : b);
                              final normalizedValue = maxXP > 0
                                  ? activity.xpEarned / maxXP
                                  : 0.0;

                              return Expanded(
                                child: AnimatedActivityBar(
                                  label: '',
                                  value: normalizedValue,
                                  xpValue: activity.xpEarned,
                                  color: AppColorRoles.primary(isDark),
                                  delay: Duration(milliseconds: index * 100),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        // Day labels row — separate from bars to ensure alignment
                        const SizedBox(height: 6),
                        Row(
                          children: activities.map((activity) {
                            String dayLabel;
                            final parsedDate = DateTime.tryParse(activity.date);
                            if (parsedDate != null) {
                              dayLabel = DateFormat(
                                'E',
                              ).format(parsedDate).substring(0, 1);
                            } else {
                              final raw = activity.date.trim();
                              dayLabel = raw.isEmpty
                                  ? '-'
                                  : raw.substring(0, 1).toUpperCase();
                            }
                            return Expanded(
                              child: Center(
                                child: Text(
                                  dayLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? AppColors.grey500
                                        : AppColors.grey600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        // Summary stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _ActivityStat(
                              label: 'profile.totalXp'.tr(),
                              value:
                                  '${activities.fold<int>(0, (sum, a) => sum + a.xpEarned)}',
                              icon: Icons.star,
                              color: AppColors.warning,
                            ),
                            _ActivityStat(
                              label: 'profile.lessons'.tr(),
                              value:
                                  '${activities.fold<int>(0, (sum, a) => sum + a.lessonsCompleted)}',
                              icon: Icons.menu_book,
                              color: AppColorRoles.primary(isDark),
                            ),
                            _ActivityStat(
                              label: 'profile.words'.tr(),
                              value:
                                  '${activities.fold<int>(0, (sum, a) => sum + a.vocabularyLearned)}',
                              icon: Icons.abc,
                              color: AppColors.greenSuccessBright,
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ActivityStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _ActivityStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.grey600),
        ),
      ],
    );
  }
}

class _WeeklyActivityDetailSheet extends StatelessWidget {
  final List<WeeklyActivityEntity> activities;

  const _WeeklyActivityDetailSheet({required this.activities});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = AppColorRoles.primary(isDark);

    final totalXP = activities.fold<int>(0, (s, a) => s + a.xpEarned);
    final totalLessons = activities.fold<int>(
      0,
      (s, a) => s + a.lessonsCompleted,
    );
    final totalWords = activities.fold<int>(
      0,
      (s, a) => s + a.vocabularyLearned,
    );
    final maxXP = activities
        .map((a) => a.xpEarned)
        .reduce((a, b) => a > b ? a : b);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'profile.weeklyActivity'.tr(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'profile.last7DaysDetailedBreakdown'.tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              // Summary row
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _SummaryChip(
                      icon: Icons.star,
                      color: AppColors.warning,
                      label: 'profile.xpValue'.tr(
                        namedArgs: {'xp': '$totalXP'},
                      ),
                      sublabel: 'profile.total'.tr(),
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      icon: Icons.menu_book,
                      color: primary,
                      label: '$totalLessons',
                      sublabel: 'profile.lessons'.tr(),
                    ),
                    const SizedBox(width: 8),
                    _SummaryChip(
                      icon: Icons.abc,
                      color: AppColors.greenSuccessBright,
                      label: '$totalWords',
                      sublabel: 'profile.words'.tr(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Day list
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: activities.length,
                  itemBuilder: (context, index) {
                    final a = activities[index];
                    final isBest = a.xpEarned == maxXP && maxXP > 0;
                    final barFraction = maxXP > 0 ? a.xpEarned / maxXP : 0.0;

                    DateTime? parsedDate = DateTime.tryParse(a.date);
                    final String dayName = parsedDate != null
                        ? DateFormat('EEEE').format(parsedDate)
                        : a.date;
                    final String shortDate = parsedDate != null
                        ? DateFormat('MMM d').format(parsedDate)
                        : '';

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isBest
                            ? primary.withValues(alpha: isDark ? 0.15 : 0.08)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.03)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isBest
                              ? primary.withValues(alpha: 0.4)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Text(
                                      dayName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (shortDate.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        shortDate,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isBest)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.warning.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.warning.withValues(
                                        alpha: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.emoji_events,
                                        size: 12,
                                        color: AppColors.warning,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'profile.bestDay'.tr(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // XP bar
                          if (a.xpEarned > 0) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: barFraction,
                                      backgroundColor: primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        primary,
                                      ),
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'profile.xpValue'.tr(
                                    namedArgs: {'xp': '${a.xpEarned}'},
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: primary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          // Stats chips
                          Row(
                            children: [
                              if (a.xpEarned == 0)
                                Text(
                                  'profile.noActivity'.tr(),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                )
                              else ...[
                                _MiniStat(
                                  icon: Icons.menu_book,
                                  color: primary,
                                  value: 'profile.lessonsCount'.tr(
                                    namedArgs: {
                                      'count': '${a.lessonsCompleted}',
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                _MiniStat(
                                  icon: Icons.abc,
                                  color: AppColors.greenSuccessBright,
                                  value: 'profile.wordsCount'.tr(
                                    namedArgs: {
                                      'count': '${a.vocabularyLearned}',
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Bottom safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        );
      },
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String sublabel;

  const _SummaryChip({
    required this.icon,
    required this.color,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
