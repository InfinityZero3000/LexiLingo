import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/screens/shop_screen.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/daily_challenges_widget.dart';

/// Level, daily challenges and boosts as one row of chips. Each opens the
/// surface that used to be a full card on Home; nothing was removed.
class ProgressChipsRow extends StatelessWidget {
  const ProgressChipsRow({super.key, this.showShopEntry = true});

  /// The boosts chip opens the shop, which is one of the locked features.
  final bool showShopEntry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer3<
      LevelProvider,
      DailyChallengesProvider,
      GamificationProvider
    >(
      builder: (context, level, challenges, gamification, _) {
        final boosts = gamification.activeBoosts;
        final chips = <Widget>[
          _ProgressChip(
            icon: Icons.workspace_premium_rounded,
            label: 'profile.level'.tr(
              namedArgs: {'level': '${level.displayLevel}'},
            ),
            tint: AppColorRoles.primary(isDark),
            foreground: AppColorRoles.primaryDeep(isDark),
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const LevelDetailsSheet(),
            ),
          ),
          if (challenges.challenges.isNotEmpty)
            _ProgressChip(
              icon: Icons.emoji_events_rounded,
              label:
                  '${'home.dailyChallenges'.tr()} '
                  '${challenges.completedCount}/${challenges.totalChallenges}',
              tint: isDark ? AppColors.purpleLight : AppColors.purple,
              foreground: isDark ? AppColors.purpleLight : AppColors.purple,
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => DailyChallengesSheet(provider: challenges),
              ),
            ),
          if (showShopEntry && boosts.isNotEmpty)
            _ProgressChip(
              icon: Icons.bolt_rounded,
              label: 'home.activeBoostsChip'.tr(
                namedArgs: {'count': '${boosts.length}'},
              ),
              tint: AppColors.orange,
              foreground: isDark ? AppColors.orange : AppColors.warningDark,
              onTap: () =>
                  LearnerRoute.push(context, (_) => const ShopScreen()),
            ),
        ];

        return Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            0,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, runSpacing: 8, children: chips),
          ),
        );
      },
    );
  }
}

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({
    required this.icon,
    required this.label,
    required this.tint,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: tint.withValues(alpha: isDark ? 0.22 : 0.14),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
