import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? change;
  final bool changePositive;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.change,
    this.changePositive = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 18),
                ),
                const Spacer(),
                if (change != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: changePositive
                          ? AppColors.successContainer
                          : AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      change!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: changePositive
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              label.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08,
                color: AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
                letterSpacing: -0.03,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WideStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final String? change;
  final bool changePositive;
  final Color? backgroundColor;
  final Color? textColor;

  const WideStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.change,
    this.changePositive = true,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = backgroundColor ?? AppColors.surface;
    final fg = textColor ?? AppColors.onSurface;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: backgroundColor == null
            ? Border.all(color: AppColors.outlineVariant, width: 0.5)
            : null,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: backgroundColor != null
                ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)
                : AppColors.primary,
            size: 28,
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08,
                    color: backgroundColor != null
                        ? Colors.white60
                        : AppColors.onSurfaceMuted,
                  ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: -0.03,
                  ),
                ),
              ],
            ),
          ),
          if (change != null)
            Text(
              change!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: changePositive ? AppColors.success : AppColors.error,
              ),
            ),
        ],
      ),
    );
  }
}
