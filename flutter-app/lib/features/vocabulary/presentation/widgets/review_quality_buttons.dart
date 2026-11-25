import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Review Quality Buttons Widget
/// Clean Code: Single responsibility - quality rating input
class ReviewQualityButtons extends StatelessWidget {
  final Function(ReviewQuality) onQualitySelected;
  final bool isLoading;

  const ReviewQualityButtons({
    super.key,
    required this.onQualitySelected,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? AppColors.surfaceDarkMuted
            : Colors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'flashcard.howWellDidYouKnow'.tr(),
            style: Theme.of(
              context,
            ).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),

          // Main quality buttons (simplified - 3 options)
          Row(
            children: [
              Expanded(
                child: _QualityButton(
                  label: 'flashcard.again'.tr(),
                  subLabel: 'flashcard.hardDifficulty'.tr(),
                  color: Theme.of(context).colorScheme.error,
                  quality: ReviewQuality.hard,
                  onPressed: isLoading ? null : onQualitySelected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QualityButton(
                  label: 'flashcard.goodDifficulty'.tr(),
                  subLabel: 'flashcard.mediumDifficulty'.tr(),
                  color: AppColors.orange,
                  quality: ReviewQuality.good,
                  onPressed: isLoading ? null : onQualitySelected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QualityButton(
                  label: 'flashcard.easyDifficulty'.tr(),
                  subLabel: 'flashcard.perfectDifficulty'.tr(),
                  color: context.status.success,
                  quality: ReviewQuality.easy,
                  onPressed: isLoading ? null : onQualitySelected,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Advanced options (collapsible)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => onQualitySelected(ReviewQuality.blackout),
                child: Text(
                  'flashcard.blackout'.tr(),
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => onQualitySelected(ReviewQuality.perfect),
                child: Text(
                  'flashcard.perfectFive'.tr(),
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  final String label;
  final String subLabel;
  final Color color;
  final ReviewQuality quality;
  final Function(ReviewQuality)? onPressed;

  const _QualityButton({
    required this.label,
    required this.subLabel,
    required this.color,
    required this.quality,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? () => onPressed!(quality) : null,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.lg,
            horizontal: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subLabel,
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  color: color.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
