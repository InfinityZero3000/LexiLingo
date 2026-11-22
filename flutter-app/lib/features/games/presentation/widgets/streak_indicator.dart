import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Fire streak indicator showing consecutive days of activity.
///
/// When streak >= 3, adds a warm glow effect.
class StreakIndicator extends StatelessWidget {
  final int streakDays;
  final bool compact;

  const StreakIndicator({
    super.key,
    required this.streakDays,
    this.compact = false,
  });

  bool get _hasGlow => streakDays >= 3;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    return _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: _hasGlow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: [
                BoxShadow(
                  color: AppColors.orange.withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
              color: AppColors.orange.withValues(alpha: 0.1),
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              color: AppColors.orange.withValues(alpha: 0.1),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: AppColors.orange,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$streakDays',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: streakDays > 0
                  ? context.status.warning
                  : AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    final color = streakDays > 0 ? context.status.warning : AppColors.textGrey;
    final bgColor = streakDays > 0
        ? AppColors.orange.withValues(alpha: 0.1)
        : AppColors.grey200;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: _hasGlow
            ? [
                BoxShadow(
                  color: AppColors.orange.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: AppColors.orange,
            size: _hasGlow ? 22 : 18,
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'common.dayCount'.plural(streakDays),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                'streak',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
