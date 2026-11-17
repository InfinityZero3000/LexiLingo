import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Session Header Widget
/// Clean Code: Single responsibility - display session progress
class SessionHeader extends StatelessWidget {
  final ReviewSessionEntity session;

  const SessionHeader({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    // One line: the bar and the count say where you are, the two chips say
    // how it is going. "Reviewed" and "Remaining" only repeated the count.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: session.progress),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: muted.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${session.reviewedCards}/${session.totalCards}',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          _StatChip(
            icon: Icons.check_circle_rounded,
            value: '${session.correctCount}',
            color: context.status.success,
            semanticLabel: 'assessment.correct'.tr(),
          ),
          const SizedBox(width: 8),
          _StatChip(
            icon: Icons.star_rounded,
            value: '+${session.totalXpEarned}',
            color: context.status.warning,
            semanticLabel: 'XP',
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  final String semanticLabel;

  const _StatChip({
    required this.icon,
    required this.value,
    required this.color,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$semanticLabel: $value',
      child: ExcludeSemantics(
        child: Material(
          color: color.withValues(alpha: 0.14),
          shape: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  value,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
