import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart'
    as glass;
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/daily_goal_sheet.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/points_calendar_dialog.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

/// Streak on the left, the daily-goal ring on the right. The ring is the one
/// "today" measure on Home; the week dots are history, not another meter.
class StreakGoalStrip extends StatelessWidget {
  const StreakGoalStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tactile =
        theme.extension<AppTactileTheme>() ?? AppTactileTheme.from(theme);
    final goalXP = context.select<SettingsProvider, int>((s) => s.dailyGoalXP);

    return Consumer2<HomeProvider, StreakProvider>(
      builder: (context, home, streakProvider, _) {
        final streak = streakProvider.streak;
        final streakDays = streak?.currentStreak ?? home.streakDays;
        final isActiveToday = streak?.isActiveToday ?? false;
        final weekly = _sevenDays(streak?.weeklyActivity ?? home.weekProgress);
        final activeDays = weekly.where((d) => d).length;
        final earnedXP = home.dailyXP;
        final percentage = goalXP > 0
            ? (earnedXP / goalXP).clamp(0.0, 1.0)
            : 0.0;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: Ink(
              decoration: tactile.decoration(
                variant: TactileSurfaceVariant.elevated,
                fill: isDark
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.white,
                accent: streakDays > 0
                    ? AppColors.deepOrange
                    : AppColorRoles.primary(isDark),
                borderRadius: BorderRadius.circular(20),
                diagnosticId: 'home-streak-goal',
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Semantics(
                        button: streak != null,
                        label: 'home.streakSemantics'.tr(
                          namedArgs: {
                            'count': '$streakDays',
                            'active': '$activeDays',
                          },
                        ),
                        child: InkWell(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(18),
                          ),
                          onTap: streak == null
                              ? null
                              : () => showPointsCalendarDialog(context, streak),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                            child: ExcludeSemantics(
                              child: Row(
                                children: [
                                  _Flame(
                                    streakDays: streakDays,
                                    isDark: isDark,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        CountUpText(
                                          value: streakDays,
                                          format: (v) => 'home.dayStreakCount'
                                              .tr(namedArgs: {'count': '$v'}),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          isActiveToday
                                              ? 'home.fireToday'.tr()
                                              : 'home.streakKeepAlive'.tr(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: AppColorRoles.textMuted(
                                                  isDark,
                                                ),
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        _WeekDots(
                                          activity: weekly,
                                          isDark: isDark,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      indent: 12,
                      endIndent: 12,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    Semantics(
                      button: true,
                      label: 'home.dailyGoalSemantics'.tr(
                        namedArgs: {
                          'earned': '$earnedXP',
                          'goal': '$goalXP',
                          'percent': '${(percentage * 100).round()}',
                        },
                      ),
                      child: InkWell(
                        borderRadius: const BorderRadius.horizontal(
                          right: Radius.circular(18),
                        ),
                        onTap: () => showDailyGoalSheet(context, home),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: ExcludeSemantics(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _GoalRing(
                                  percentage: percentage,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '$earnedXP/$goalXP XP',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: percentage >= 1
                                        ? _success(isDark)
                                        : AppColorRoles.primaryDeep(isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static List<bool> _sevenDays(List<bool> source) =>
      List<bool>.generate(7, (i) => i < source.length && source[i]);

  static Color _success(bool isDark) =>
      isDark ? AppColors.successNeon : AppColors.greenSuccess;
}

class _Flame extends StatelessWidget {
  const _Flame({required this.streakDays, required this.isDark});

  final int streakDays;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final hasStreak = streakDays > 0;
    final ring = hasStreak
        ? AppColors.deepOrange
        : AppColors.grey500.withValues(alpha: 0.5);
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hasStreak
            ? AppColors.deepOrange.withValues(alpha: isDark ? 0.22 : 0.12)
            : AppColors.grey500.withValues(alpha: 0.12),
        border: Border.all(color: ring, width: 2),
      ),
      child: Center(child: _glyph(hasStreak)),
    );
  }

  Widget _glyph(bool hasStreak) {
    if (!hasStreak) {
      return const Icon(
        Icons.local_fire_department_rounded,
        size: 28,
        color: AppColors.grey500,
      );
    }
    if (streakDays >= 30) {
      return const LottieAnimationWidget.fire(width: 36, height: 36);
    }
    if (streakDays >= 7) {
      return const LottieAnimationWidget.flame(width: 36, height: 36);
    }
    return ShaderMask(
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.accentYellow,
          AppColors.deepOrange,
          AppColors.errorDark,
        ],
      ).createShader(bounds),
      child: const Icon(
        Icons.local_fire_department_rounded,
        size: 28,
        color: Colors.white,
      ),
    );
  }
}

class _WeekDots extends StatelessWidget {
  const _WeekDots({required this.activity, required this.isDark});

  final List<bool> activity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().weekday; // 1 = Mon … 7 = Sun
    final idle = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: activity[i] ? AppColors.deepOrange : idle,
              border: i + 1 == today
                  ? Border.all(color: AppColors.deepOrange, width: 2)
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({required this.percentage, required this.isDark});

  final double percentage;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = percentage >= 1;
    final accent = AppColorRoles.primary(isDark);
    final success = StreakGoalStrip._success(isDark);
    final successDeep = isDark ? AppColors.successNeon : AppColors.greenSuccess;

    // A small pop the moment the goal completes — keyed on `done`, so it
    // fires once per transition and never loops.
    return TweenAnimationBuilder<double>(
      key: ValueKey(done),
      tween: Tween(begin: done ? 0.8 : 1, end: 1),
      duration: homeMotion(context, 500),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: glass.AnimatedProgressRing(
        progress: percentage,
        size: 56,
        strokeWidth: 6,
        duration: homeMotion(context, 800),
        backgroundColor: (done ? success : accent).withValues(alpha: 0.15),
        gradientColors: done
            ? [success, successDeep]
            : AppColorRoles.primaryGradient(isDark),
        child: done
            ? Icon(Icons.check_rounded, color: success, size: 24)
            : Text(
                '${(percentage * 100).round()}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColorRoles.primaryDeep(isDark),
                ),
              ),
      ),
    );
  }
}
