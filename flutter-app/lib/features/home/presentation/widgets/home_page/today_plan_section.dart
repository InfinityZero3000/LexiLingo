import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/today_plan_models.dart';

/// Full task tile for the Today's Plan page. Home shows tasks inside the
/// "Up next" hero instead (see next_up_hero.dart).
class TodayPlanTaskTile extends StatelessWidget {
  const TodayPlanTaskTile({super.key, required this.task, required this.onTap});

  final TodayPlanTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final muted = AppColorRoles.textMuted(isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: task.isCompleted
                ? task.color.withValues(alpha: 0.10)
                : colorScheme.surface.withValues(alpha: isDark ? 0.36 : 0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: task.isCompleted
                  ? task.color.withValues(alpha: 0.32)
                  : colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: task.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(task.icon, color: task.color, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 5,
                        value: task.progress,
                        backgroundColor: task.color.withValues(alpha: 0.12),
                        valueColor: AlwaysStoppedAnimation<Color>(task.color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (task.rewardLabel != null)
                    Text(
                      task.rewardLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: task.color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (task.metaLabel != null)
                    Text(
                      task.metaLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 5),
                  Icon(
                    task.isCompleted
                        ? Icons.check_circle_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: task.isCompleted ? task.color : muted,
                    size: task.isCompleted ? 18 : 14,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
