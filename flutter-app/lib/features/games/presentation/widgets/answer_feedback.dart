import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

enum AnswerVerdict { correct, wrong, timeout }

/// Explanation shown under the options after an answer. It stays on screen
/// until the learner taps [GameNextBar]; nothing here auto-dismisses.
class AnswerFeedbackPanel extends StatelessWidget {
  final AnswerVerdict verdict;
  final String? chosen;
  final String? correctAnswer;
  final String? completedText;
  final String? explanation;
  final String? ruleTip;
  final String? extra;
  final String? explanationLabel;

  const AnswerFeedbackPanel({
    super.key,
    required this.verdict,
    this.chosen,
    this.correctAnswer,
    this.completedText,
    this.explanation,
    this.ruleTip,
    this.extra,
    this.explanationLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (verdict) {
      AnswerVerdict.correct => AppColors.greenSuccess,
      AnswerVerdict.wrong => AppColors.errorBright,
      AnswerVerdict.timeout => AppColors.orange,
    };
    final icon = switch (verdict) {
      AnswerVerdict.correct => Icons.check_circle_rounded,
      AnswerVerdict.wrong => Icons.cancel_rounded,
      AnswerVerdict.timeout => Icons.timer_off_rounded,
    };
    final title = switch (verdict) {
      AnswerVerdict.correct => 'games.answerFeedback.correctTitle',
      AnswerVerdict.wrong => 'games.answerFeedback.wrongTitle',
      AnswerVerdict.timeout => 'games.answerFeedback.timeoutTitle',
    }.tr();

    final why = _clean(explanation);
    var rule = _clean(ruleTip);
    if (rule == why) rule = null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (verdict != AnswerVerdict.correct && chosen != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Line(
              label: 'games.answerFeedback.yourAnswer'.tr(),
              value: chosen!.isEmpty
                  ? 'games.answerFeedback.noAnswer'.tr()
                  : chosen!,
              color: AppColors.errorBright,
            ),
          ],
          if (correctAnswer != null && correctAnswer!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _Line(
              label: 'games.answerFeedback.correctAnswer'.tr(),
              value: correctAnswer!,
              color: AppColors.greenSuccess,
            ),
          ],
          if (completedText != null && completedText!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              completedText!,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontStyle: FontStyle.italic,
                height: 1.4,
                color: scheme.onSurface,
              ),
            ),
          ],
          if (why != null) ...[
            const SizedBox(height: AppSpacing.md),
            _Section(
              label: explanationLabel ?? 'games.answerFeedback.whyLabel'.tr(),
              body: why,
            ),
          ],
          if (rule != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _Section(label: 'games.answerFeedback.ruleLabel'.tr(), body: rule),
          ],
          if (extra != null && extra!.trim().isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              extra!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.4,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

class _Line extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Line({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final String body;
  const _Section({required this.label, required this.body});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.5,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

/// Pinned bottom button that moves the game on once the learner has read the
/// feedback.
class GameNextBar extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const GameNextBar({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textInverted,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
