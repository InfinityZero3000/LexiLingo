import 'dart:math';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Small pill label (e.g. "MULTIPLE CHOICE")
class ExerciseBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  const ExerciseBadge(this.label, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: colors.primary),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall!.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primary,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded option card (pill or rect)
class ExerciseOptionCard extends StatelessWidget {
  final String text;
  final String? label; // letter or number shown on left/right
  final bool labelOnRight;
  final bool showRadio; // radio circle on right
  final bool isSelected;
  final bool isCorrect; // only meaningful when isAnswered
  final bool isAnswered;
  final VoidCallback? onTap;
  final double radius;

  const ExerciseOptionCard({
    super.key,
    required this.text,
    this.label,
    this.labelOnRight = false,
    this.showRadio = false,
    required this.isSelected,
    required this.isCorrect,
    required this.isAnswered,
    this.onTap,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    Color bg = colors.card;
    Color border = colors.border;
    Color fg = colors.textPrimary;

    final status = context.status;
    final scheme = Theme.of(context).colorScheme;
    final revealCorrect = isAnswered && isCorrect;
    final revealWrong = isAnswered && isSelected && !isCorrect;
    if (revealCorrect) {
      bg = status.success;
      border = status.success;
      fg = status.onSuccess;
    } else if (revealWrong) {
      bg = scheme.error;
      border = scheme.error;
      fg = scheme.onError;
    } else if (!isAnswered && isSelected) {
      bg = colors.primary;
      border = colors.primary;
      fg = Colors.white;
    }

    final labelWidget = label == null
        ? null
        : Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? fg.withValues(alpha: 0.5) : colors.border,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Text(
              label!,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                fontWeight: FontWeight.w700,
                color: isSelected ? fg : colors.textSecondary,
              ),
            ),
          );

    return GestureDetector(
      onTap: isAnswered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border, width: 1.5),
          boxShadow: isAnswered
              ? []
              : [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          children: [
            if (!labelOnRight && labelWidget != null) ...[
              labelWidget,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (labelOnRight && labelWidget != null) ...[
              const SizedBox(width: 14),
              labelWidget,
            ],
            if (showRadio) ...[
              const SizedBox(width: 10),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 22,
                color: isSelected ? fg : colors.border,
              ),
            ],
            if (revealCorrect || revealWrong)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Icon(
                  isCorrect
                      ? Icons.check_circle_outline
                      : Icons.cancel_outlined,
                  size: 20,
                  color: fg,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Explanation panel shown after answering
class ExerciseExplanationCard extends StatelessWidget {
  final String? explanation;
  final bool isCorrect;
  final String? correctAnswer;
  final bool pairAnswer;

  const ExerciseExplanationCard({
    super.key,
    this.explanation,
    required this.isCorrect,
    this.correctAnswer,
    this.pairAnswer = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasExplanation = explanation != null && explanation!.isNotEmpty;
    // Always surface the right answer on a miss — these are practice
    // exercises, not graded tests, so the learner needs it to self-correct.
    final showCorrectAnswer =
        !isCorrect && correctAnswer != null && correctAnswer!.isNotEmpty;
    if (!hasExplanation && !showCorrectAnswer) return const SizedBox.shrink();

    // The bright kCorrect / kError greens and reds are for fills and icons; as
    // text on their own 8% tint they measured 2.1:1. The container tokens are
    // the pair built to be read together.
    final status = context.status;
    final scheme = Theme.of(context).colorScheme;
    final bg = isCorrect ? status.successContainer : scheme.errorContainer;
    final fg = isCorrect ? status.onSuccessContainer : scheme.onErrorContainer;

    return _ScrollIntoView(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: fg.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasExplanation)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isCorrect ? Icons.check_circle : Icons.info_outline,
                    color: fg,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      explanation!,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: fg,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            if (showCorrectAnswer) ...[
              if (hasExplanation) const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, color: fg, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: pairAnswer
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'lesson.exercise.correctAnswerLabel'.tr(),
                                style: Theme.of(context).textTheme.bodyMedium!
                                    .copyWith(
                                      color: fg,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              PairAnswerChips(
                                pairs: parsePairAnswer(correctAnswer!),
                              ),
                            ],
                          )
                        : Text(
                            '${'lesson.exercise.correctAnswerLabel'.tr()}: $correctAnswer',
                            style: Theme.of(context).textTheme.bodyMedium!
                                .copyWith(
                                  color: fg,
                                  fontWeight: FontWeight.w600,
                                  height: 1.5,
                                ),
                          ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Brings its child into view once, when it first appears: after an answer the
/// explanation lands below the fold on a phone with long options, behind the
/// action bar, and the learner had to scroll to find out why they were wrong.
class _ScrollIntoView extends StatefulWidget {
  const _ScrollIntoView({required this.child});

  final Widget child;

  @override
  State<_ScrollIntoView> createState() => _ScrollIntoViewState();
}

class _ScrollIntoViewState extends State<_ScrollIntoView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      Scrollable.ensureVisible(
        context,
        duration: still ? Duration.zero : const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Circular blue button that plays TTS audio
class CircleAudioButton extends StatelessWidget {
  final String text;
  final String? audioUrl;
  final double size;
  const CircleAudioButton({
    super.key,
    required this.text,
    this.audioUrl,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: SpeakIconButton(
        text: text,
        audioUrl: audioUrl,
        size: size * 0.45,
        color: Colors.white,
      ),
    );
  }
}

/// The first quoted phrase and the text around it, so a question can be shown
/// with the phrase highlighted and its own punctuation left where it was.
/// Single quotes are tried before double, like [extractQuotedWord].
({String before, String quoted, String after})? splitAroundQuote(String text) {
  for (final pattern in [RegExp("'([^']+)'"), RegExp('"([^"]+)"')]) {
    final match = pattern.firstMatch(text);
    if (match != null) {
      return (
        before: text.substring(0, match.start),
        quoted: match.group(1)!,
        after: text.substring(match.end),
      );
    }
  }
  return null;
}

/// Extract first quoted word from text — tries single then double quotes
String extractQuotedWord(String text) {
  final s = RegExp("'([^']+)'").firstMatch(text);
  if (s != null) return s.group(1)!;
  final d = RegExp('"([^"]+)"').firstMatch(text);
  if (d != null) return d.group(1)!;
  return '';
}

/// Parses the pair-exercise storage format ("key1:value1, key2:value2")
/// into word → match. Used by matching/categorization widgets both to grade
/// each pair individually and to render the answer as chips instead of raw
/// punctuation.
Map<String, String> parsePairAnswer(String raw) {
  final map = <String, String>{};
  for (final part in raw.split(',')) {
    final trimmed = part.trim();
    final sep = trimmed.indexOf(':');
    if (sep == -1) continue;
    map[trimmed.substring(0, sep).trim()] = trimmed.substring(sep + 1).trim();
  }
  return map;
}

/// A matched-pair reveal rendered as chips ("word → meaning") rather than
/// the raw "word:meaning, word:meaning" storage string, which reads like code.
class PairAnswerChips extends StatelessWidget {
  final Map<String, String> pairs;
  const PairAnswerChips({super.key, required this.pairs});

  @override
  Widget build(BuildContext context) {
    if (pairs.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: pairs.entries
          .map(
            (e) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kCorrect.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: kCorrect.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    e.key,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: kCorrect,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: kCorrect,
                    ),
                  ),
                  Text(
                    e.value,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: kCorrect,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Body of an exercise that must stay usable on a small screen: scrolls when
/// the content is taller than the space, and centres it vertically when there
/// is room to spare (a fixed Column with Spacers overflowed instead).
class ExerciseScrollBody extends StatelessWidget {
  final List<Widget> children;
  const ExerciseScrollBody({super.key, required this.children});

  static const _padding = EdgeInsets.fromLTRB(
    20,
    AppSpacing.xl,
    20,
    AppSpacing.lg,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: _padding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: max(0, box.maxHeight - _padding.vertical),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}
