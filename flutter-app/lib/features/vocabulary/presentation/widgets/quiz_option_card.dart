import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// A single multiple-choice option in the vocabulary quiz.
/// Renders neutral / selected / correct / wrong states after answering.
class QuizOptionCard extends StatelessWidget {
  final int index;
  final String text;
  final bool answered;
  final bool isCorrect;
  final bool isSelected;
  final VoidCallback? onTap;

  const QuizOptionCard({
    super.key,
    required this.index,
    required this.text,
    required this.answered,
    required this.isCorrect,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final baseSurface = isDark ? AppColors.surfaceDarkMuted : Colors.white;

    Color borderColor = theme.colorScheme.outlineVariant;
    Color background = baseSurface;
    Color numberColor = theme.colorScheme.onSurfaceVariant;
    Color numberBg = theme.colorScheme.surfaceContainerHighest;
    IconData? trailingIcon;
    Color? trailingColor;

    if (answered) {
      if (isCorrect) {
        borderColor = context.status.success;
        background = context.status.success.withValues(alpha: 0.12);
        numberColor = Colors.white;
        numberBg = context.status.success;
        trailingIcon = Icons.check_circle_rounded;
        trailingColor = context.status.success;
      } else if (isSelected) {
        borderColor = Theme.of(context).colorScheme.error;
        background = Theme.of(
          context,
        ).colorScheme.error.withValues(alpha: 0.10);
        numberColor = Colors.white;
        numberBg = Theme.of(context).colorScheme.error;
        trailingIcon = Icons.cancel_rounded;
        trailingColor = Theme.of(context).colorScheme.error;
      } else {
        borderColor = theme.colorScheme.outlineVariant.withValues(alpha: 0.4);
        background = baseSurface.withValues(alpha: 0.5);
      }
    }

    return Semantics(
      button: true,
      selected: isSelected,
      label: text,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: Material(
          color: background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Container(
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: borderColor, width: 2),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: numberBg,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$index',
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: numberColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 10),
                    Icon(trailingIcon, color: trailingColor, size: 24),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
