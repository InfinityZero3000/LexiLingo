import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';

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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1C2632)
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'How well did you know this?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          
          // Main quality buttons (simplified - 3 options)
          Row(
            children: [
              Expanded(
                child: _QualityButton(
                  label: 'Again',
                  subLabel: 'Hard',
                  color: Colors.red,
                  quality: ReviewQuality.hard,
                  onPressed: isLoading ? null : onQualitySelected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QualityButton(
                  label: 'Good',
                  subLabel: 'Medium',
                  color: Colors.orange,
                  quality: ReviewQuality.good,
                  onPressed: isLoading ? null : onQualitySelected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QualityButton(
                  label: 'Easy',
                  subLabel: 'Perfect!',
                  color: Colors.green,
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
                  'Blackout (0)',
                  style: TextStyle(
                    color: AppColors.textGrey.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ),
              TextButton(
                onPressed: isLoading
                    ? null
                    : () => onQualitySelected(ReviewQuality.perfect),
                child: Text(
                  'Perfect (5)',
                  style: TextStyle(
                    color: AppColors.textGrey.withOpacity(0.7),
                    fontSize: 12,
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
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: color.withOpacity(0.3),
              width: 2,
            ),
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
                style: TextStyle(
                  color: color.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
