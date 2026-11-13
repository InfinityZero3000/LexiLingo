import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

Future<void> showDailyGoalSheet(
  BuildContext context,
  HomeProvider homeProvider,
) async {
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
                          style: Theme.of(sheetContext).textTheme.headlineSmall
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
                              SnackBar(content: Text(settingsProvider.error!)),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                Icon(Icons.check_circle, color: primaryColor),
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
