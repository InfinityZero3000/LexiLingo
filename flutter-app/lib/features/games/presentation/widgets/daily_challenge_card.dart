import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/games/presentation/theme/game_palette.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';

/// Daily challenge card displayed on the Games Hub.
///
/// Shows the challenge game type icon, description, 2x XP bonus badge,
/// a countdown label, and a completed checkmark state.
class DailyChallengeCard extends StatelessWidget {
  final DailyChallenge challenge;
  final VoidCallback onTap;
  final bool allowCompletedTap;

  const DailyChallengeCard({
    super.key,
    required this.challenge,
    required this.onTap,
    this.allowCompletedTap = false,
  });

  /// Map apiKey → matching GameType, returning null when unknown.
  static GameType? _gameTypeFromKey(String key) {
    for (final t in GameType.values) {
      if (t.apiKey == key) return t;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final gameType = _gameTypeFromKey(challenge.gameType);
    final icon = gameType?.icon ?? Icons.sports_esports_rounded;
    final completed = challenge.completed;

    return GestureDetector(
      onTap: completed && !allowCompletedTap ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          gradient: completed
              ? null
              : const LinearGradient(
                  colors: GamePalette.skySoftGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
          color: completed ? AppColors.grey200 : null,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: completed
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: completed
                    ? AppColors.grey300
                    : AppColors.textInverted.withValues(alpha: 0.2),
              ),
              alignment: Alignment.center,
              child: completed
                  ? Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.greenSuccess,
                      size: 28,
                    )
                  : Icon(
                      icon,
                      color: Theme.of(context).colorScheme.surface,
                      size: 26,
                    ),
            ),
            const SizedBox(width: AppSpacing.lg),

            // Description + timer
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    completed
                        ? 'games.challengeCompleted'.tr()
                        : 'games.dailyChallengeLabel'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: completed
                          ? AppColors.textGrey
                          : AppColors.textInverted.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    challenge.description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: completed
                          ? AppColors.textDark
                          : AppColors.textInverted,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'games.resetsTomorrow'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: completed
                          ? AppColors.textGrey
                          : AppColors.textInverted.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),

            // 2x XP badge (only when incomplete)
            if (!completed)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accentYellow,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${challenge.bonusMultiplier}x',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.surfaceLight,
                        height: 1,
                      ),
                    ),
                    Text(
                      'XP',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.surfaceLight,
                      ),
                    ),
                  ],
                ),
              )
            else
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.greenSuccess,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}
