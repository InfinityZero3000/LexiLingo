import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart'
    as glass;
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

void _showDailyGoalSheet(BuildContext context, HomeProvider homeProvider) async {
  final settings = context.read<SettingsProvider>();
  final settingsState = settings.settings;

  if (settingsState == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('home.dailyGoalSettingsPending'.tr())),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
      final colorScheme = Theme.of(sheetContext).colorScheme;
      final primaryColor = AppColorRoles.primary(isDark);

      return Consumer<SettingsProvider>(
        builder: (sheetContext, settingsProvider, _) {
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            decoration: BoxDecoration(
              color: Theme.of(sheetContext).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Text(
                    'home.dailyGoal'.tr(),
                    style: Theme.of(sheetContext).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'home.dailyGoalDescription'.tr(),
                    style: Theme.of(sheetContext).textTheme.bodyMedium
                        ?.copyWith(color: AppColorRoles.textMuted(isDark)),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          primaryColor,
                          primaryColor.withValues(alpha: 0.72),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${homeProvider.dailyXP}/${settingsProvider.dailyGoalXP} XP',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: colorScheme.onPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'settings.goal_progress'.tr(
                            namedArgs: {
                              'percent':
                                  '${(homeProvider.dailyProgressPercentage * 100).toInt()}',
                            },
                          ),
                          style: Theme.of(sheetContext).textTheme.bodyMedium
                              ?.copyWith(
                                color: colorScheme.onPrimary.withValues(
                                  alpha: 0.88,
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...SettingsProvider.dailyGoalPresets.map((goal) {
                    final xp = goal['xp'] as int;
                    final isSelected = settingsProvider.dailyGoalXP == xp;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          await settingsProvider.updateDailyGoal(xp);
                          if (!sheetContext.mounted) return;

                          if (settingsProvider.error == null) {
                            homeProvider.updateDailyGoalTarget(xp);
                            Navigator.of(sheetContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'settings.goal_updated'.tr(
                                    namedArgs: {'xp': '$xp'},
                                  ),
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              SnackBar(
                                content: Text(settingsProvider.error!),
                              ),
                            );
                          }
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? primaryColor.withValues(alpha: 0.12)
                                : colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? primaryColor
                                  : colorScheme.outlineVariant,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? primaryColor
                                      : primaryColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  goal['icon'] as IconData,
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : primaryColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${(goal['label'] as String).tr()} • $xp XP',
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      (goal['description'] as String).tr(),
                                      style: Theme.of(sheetContext)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColorRoles.textMuted(
                                              isDark,
                                            ),
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                AppGameIcon(
                                  GameIcon.checkmark,
                                  size: 24,
                                  fallbackColor: primaryColor,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class LevelAndDailyGoalRow extends StatelessWidget {
  const LevelAndDailyGoalRow({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 360;

          if (isNarrow) {
            return Column(
              children: [
                SizedBox(height: 148, child: LevelProgressCard(compact: true)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 148,
                  child: _DailyGoalCard(
                    provider: provider,
                    compact: true,
                    margin: EdgeInsets.zero,
                  ),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: SizedBox(
                  height: 148,
                  child: LevelProgressCard(compact: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: SizedBox(
                  height: 148,
                  child: _DailyGoalCard(
                    provider: provider,
                    compact: true,
                    margin: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DailyGoalCard extends StatelessWidget {
  final HomeProvider provider;
  final bool compact;
  final EdgeInsetsGeometry? margin;

  const _DailyGoalCard({
    required this.provider,
    this.compact = false,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Use user-configured daily goal from settings; fall back to HomeProvider.
    final goalXP = context.read<SettingsProvider>().dailyGoalXP;
    final earnedXP = provider.dailyXP;
    final percentage = goalXP > 0 ? (earnedXP / goalXP).clamp(0.0, 1.0) : 0.0;
    final isCompleted = percentage >= 1.0;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = AppColorRoles.primary(isDark);
    final accentDeep = AppColorRoles.primaryDeep(isDark);
    final surfaceBg = colorScheme.surfaceContainerHighest;
    final compactBg = isCompleted
        ? AppColors.greenSuccessBright.withValues(alpha: 0.10)
        : accent.withValues(alpha: 0.07);
    final cardPadding = compact ? 14.0 : 20.0;
    final ringSize = compact ? 58.0 : 70.0;
    final ringStroke = compact ? 5.0 : 6.0;
    final titleFontSize = compact ? 16.0 : null;
    final valueFontSize = compact ? 18.0 : null;
    final chipFontSize = compact ? 11.0 : 12.0;
    final badgeIconSize = compact ? 16.0 : 18.0;
    final ringValueFontSize = compact ? 12.0 : 14.0;

    final borderRadius = BorderRadius.circular(compact ? 16 : 20);

    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: margin ?? const EdgeInsets.symmetric(horizontal: 16),
        child: InkWell(
          onTap: () => _showDailyGoalSheet(context, provider),
          borderRadius: borderRadius,
          child: Ink(
            padding: EdgeInsets.all(cardPadding),
            decoration: BoxDecoration(
              color: compact ? compactBg : surfaceBg,
              borderRadius: borderRadius,
              border: Border.all(
                color: isCompleted
                    ? AppColors.greenSuccessBright.withValues(alpha: 0.3)
                    : accent.withValues(alpha: 0.35),
              ),
            ),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: colorScheme.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: isCompleted
                                ? AppGameIcon(
                                    GameIcon.trophy,
                                    size: badgeIconSize,
                                    fallbackColor: AppColors.greenSuccessBright,
                                  )
                                : AppGameIcon(
                                    GameIcon.bolt,
                                    size: badgeIconSize,
                                    fallbackColor: accent,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'home.dailyGoal'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: isCompleted
                                        ? AppColors.greenSuccess
                                        : accentDeep,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: Center(
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.surface,
                            ),
                            child: glass.AnimatedProgressRing(
                              progress: percentage.clamp(0.0, 1.0),
                              size: ringSize + 10,
                              strokeWidth: ringStroke,
                              gradientColors: isCompleted
                                  ? const [
                                      AppColors.greenSuccessBright,
                                      AppColors.greenSuccess,
                                    ]
                                  : AppColorRoles.primaryGradient(isDark),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isCompleted)
                                    const AppGameIcon(
                                      GameIcon.checkmark,
                                      size: 20,
                                      fallbackColor:
                                          AppColors.greenSuccessBright,
                                    )
                                  else
                                    Text(
                                      '${(percentage * 100).toInt()}%',
                                      style: TextStyle(
                                        fontSize: ringValueFontSize,
                                        fontWeight: FontWeight.bold,
                                        color: accent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$earnedXP/$goalXP XP',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isCompleted
                                  ? AppColors.greenSuccessBright
                                  : accent,
                            ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      // Animated Progress Ring
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.surface,
                        ),
                        child: glass.AnimatedProgressRing(
                          progress: percentage.clamp(0.0, 1.0),
                          size: ringSize,
                          strokeWidth: ringStroke,
                          gradientColors: isCompleted
                              ? const [
                                  AppColors.greenSuccessBright,
                                  AppColors.greenSuccess,
                                ]
                              : const [AppColors.primary, AppColors.primary],
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isCompleted)
                                const AppGameIcon(
                                  GameIcon.checkmark,
                                  size: 22,
                                  fallbackColor: AppColors.greenSuccessBright,
                                )
                              else
                                Text(
                                  '${(percentage * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: ringValueFontSize,
                                    fontWeight: FontWeight.bold,
                                    color: isCompleted
                                        ? AppColors.greenSuccessBright
                                        : AppColors.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 12 : 20),
                      // Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(compact ? 5 : 6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surface,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: isCompleted
                                      ? AppGameIcon(
                                          GameIcon.trophy,
                                          size: badgeIconSize,
                                          fallbackColor:
                                              AppColors.greenSuccessBright,
                                        )
                                      : AppGameIcon(
                                          GameIcon.bolt,
                                          size: badgeIconSize,
                                          fallbackColor: accent,
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'home.dailyXpGoal'.tr(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: titleFontSize,
                                          color: isCompleted
                                              ? AppColors.greenSuccess
                                              : accentDeep,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: compact ? 6 : 8),
                            Text(
                              '$earnedXP/$goalXP XP',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: valueFontSize,
                                    color: isCompleted
                                        ? AppColors.greenSuccessBright
                                        : accent,
                                  ),
                            ),
                            SizedBox(height: compact ? 2 : 4),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: compact ? 8 : 10,
                                vertical: compact ? 3 : 4,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  isCompleted
                                      ? AppGameIcon(
                                          GameIcon.giftBox,
                                          size: 14,
                                          fallbackColor:
                                              AppColors.greenSuccessBright,
                                        )
                                      : Icon(
                                          Icons.trending_up,
                                          size: 14,
                                          color: accent,
                                        ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isCompleted
                                        ? 'home.goalCompleted'.tr()
                                        : 'home.keepGoing'.tr(),
                                    style: TextStyle(
                                      fontSize: chipFontSize,
                                      fontWeight: FontWeight.w600,
                                      color: isCompleted
                                          ? AppColors.greenSuccessBright
                                          : accent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
