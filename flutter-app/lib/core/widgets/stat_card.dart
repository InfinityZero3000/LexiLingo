import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

/// One metric: label, value, optional trend and note.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.trend,
    this.note,
    this.icon,
    this.accent,
    this.loading = false,
    this.onTap,
  });

  final String label;
  final String value;

  /// Signed change, e.g. `+12%`; a leading `-` is shown as negative.
  final String? trend;
  final String? note;
  final IconData? icon;
  final Color? accent;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = accent ?? scheme.primary;
    final negative = trend?.trimLeft().startsWith('-') ?? false;
    final trendColor = negative ? scheme.error : context.status.success;

    return Material(
      color: scheme.surface,
      borderRadius: AppRadius.lgAll,
      elevation: 0,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: loading
              ? const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 72, height: 12),
                    SizedBox(height: AppSpacing.md),
                    SkeletonBox(width: 104, height: 28),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: color),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      value,
                      style: theme.textTheme.heading?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (trend != null || note != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          if (trend != null)
                            Text(
                              trend!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: trendColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (trend != null && note != null)
                            const SizedBox(width: AppSpacing.sm),
                          if (note != null)
                            Expanded(
                              child: Text(
                                note!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

enum StatusTone { success, warning, info, danger, neutral }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;
    final (background, foreground) = switch (tone) {
      StatusTone.success => (
        status.successContainer,
        status.onSuccessContainer,
      ),
      StatusTone.warning => (
        status.warningContainer,
        status.onWarningContainer,
      ),
      StatusTone.info => (status.infoContainer, status.info),
      StatusTone.danger => (scheme.errorContainer, scheme.onErrorContainer),
      StatusTone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
