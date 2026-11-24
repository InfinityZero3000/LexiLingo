import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/gamification/presentation/theme/reward_palette.dart';

import 'package:lexilingo_app/core/theme/app_theme.dart';

class StarterRewardDialog extends StatelessWidget {
  final int gems;

  const StarterRewardDialog({super.key, required this.gems});

  static Future<void> show(BuildContext context, {required int gems}) {
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'gamification.starterReward.title'.tr(),
      transitionDuration: disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => StarterRewardDialog(gems: gems),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Theme.of(context).shadowColor.withValues(alpha: 0.52),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 390),
            child: Container(
              margin: const EdgeInsets.all(AppSpacing.xl),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                30,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).shadowColor.withValues(alpha: 0.22),
                    blurRadius: 36,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    label: 'gamification.starterReward.gemLabel'.tr(),
                    // Bounce-in — the "reward granted" beat, elasticOut needs
                    // no controller since TweenAnimationBuilder self-drives.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 650),
                      curve: Curves.elasticOut,
                      builder: (_, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: RewardPalette.starterGradient,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentMint.withValues(
                                alpha: 0.35,
                              ),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.diamond_rounded,
                          size: 58,
                          color: AppColors.surfaceLight,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'gamification.starterReward.title'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '+$gems GEM',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: isDark
                          ? AppColors.accentMint
                          : RewardPalette.starterIndigo,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'gamification.starterReward.description'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                        backgroundColor: AppColors.accentMint,
                        foregroundColor: AppColors.textDark,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll,
                        ),
                      ),
                      child: Text(
                        'gamification.starterReward.action'.tr(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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
