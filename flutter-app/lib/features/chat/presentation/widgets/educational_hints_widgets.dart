import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/educational_hints.dart';
import '../helpers/grammar_label.dart';
import 'markdown_message_content.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

// These cards use fixed light backgrounds, so markdown is always rendered light.
Widget _md(String text, TextStyle style) => MarkdownMessageContent(
  content: text,
  isDark: false,
  selectable: false,
  baseTextStyle: style,
);

/// Educational Hints Card
/// Displays grammar corrections and vocabulary hints from AI response
class EducationalHintsCard extends StatelessWidget {
  final EducationalHints hints;

  /// Called with a correction when the learner taps "save" on it — the
  /// caller owns persistence (e.g. into the Mistake Notebook).
  final void Function(GrammarCorrection correction)? onSaveMistake;

  /// Called with a vocabulary hint when the learner taps "save" on it.
  final void Function(VocabularyHint hint)? onSaveWord;

  /// Called when the learner taps "Practice this" on a grammar correction —
  /// routes to a real practice destination, not just a chat reply.
  final void Function(GrammarCorrection correction)? onPracticeGrammar;

  /// Called when the learner taps the mic on a vocabulary hint — opens
  /// pronunciation practice for that word/example.
  final void Function(VocabularyHint hint)? onPracticePronunciation;

  const EducationalHintsCard({
    super.key,
    required this.hints,
    this.onSaveMistake,
    this.onSaveWord,
    this.onPracticeGrammar,
    this.onPracticePronunciation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grammar corrections
          if (hints.grammarCorrections.isNotEmpty)
            ...hints.grammarCorrections.map(
              (correction) => GrammarCorrectionBadge(
                correction: correction,
                onSave: onSaveMistake == null
                    ? null
                    : () => onSaveMistake!(correction),
                onPractice: onPracticeGrammar == null
                    ? null
                    : () => onPracticeGrammar!(correction),
              ),
            ),

          // Vocabulary hints
          if (hints.vocabularyHints.isNotEmpty)
            ...hints.vocabularyHints.map(
              (hint) => VocabularyHintCard(
                hint: hint,
                onSave: onSaveWord == null ? null : () => onSaveWord!(hint),
                onPracticePronunciation: onPracticePronunciation == null
                    ? null
                    : () => onPracticePronunciation!(hint),
              ),
            ),

          // Encouragement
          if (hints.encouragement != null && hints.encouragement!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.thumb_up, size: 14, color: context.status.success),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      hints.encouragement!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.status.success,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Grammar Correction Badge
/// Shows the learner's wrong text, the corrected text and a one-line reason.
class GrammarCorrectionBadge extends StatelessWidget {
  final GrammarCorrection correction;
  final VoidCallback? onSave;
  final VoidCallback? onPractice;

  const GrammarCorrectionBadge({
    super.key,
    required this.correction,
    this.onSave,
    this.onPractice,
  });

  @override
  Widget build(BuildContext context) {
    final original = correction.original.trim();
    final corrected = correction.corrected.trim();
    if (original.isEmpty || corrected.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final status = context.status;
    final textTheme = theme.textTheme;
    final ink = status.onWarningContainer;
    final explanation = correction.explanation.trim();
    final labelKey = grammarLabelIsInformative(correction.errorType)
        ? grammarLabelKey(correction.errorType)
        : null;
    final showPractice =
        onPractice != null && grammarLabelHasPractice(correction.errorType);

    // Material, not a decorated Container, so the save button's ink shows.
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: status.warningContainer,
        borderRadius: AppRadius.mdAll,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note, size: 18, color: ink),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(
                              child: Text(
                                'chat.fixSuggestion'.tr(),
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (labelKey != null)
                          StatusPill(
                            label: labelKey.tr(),
                            tone: StatusTone.warning,
                          ),
                      ],
                    ),
                  ),
                  if (onSave != null)
                    Semantics(
                      button: true,
                      label: 'chat.saveCorrection'.tr(),
                      child: ExcludeSemantics(
                        child: InkResponse(
                          onTap: onSave,
                          radius: kMinTapTarget / 2,
                          child: TapTargetBox(
                            child: Icon(
                              Icons.bookmark_add_outlined,
                              size: 20,
                              color: ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _CorrectionLine(
                icon: Icons.close_rounded,
                iconColor: theme.colorScheme.error,
                child: Text(
                  original,
                  style: textTheme.bodyMedium?.copyWith(
                    color: ink,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _CorrectionLine(
                icon: Icons.check_rounded,
                iconColor: status.success,
                child: _themedMd(
                  context,
                  corrected,
                  textTheme.bodyMedium!.copyWith(
                    color: ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (explanation.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _themedMd(
                  context,
                  explanation,
                  textTheme.bodySmall!.copyWith(color: ink),
                ),
              ],
              if (showPractice)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: ActionChip(
                    avatar: Icon(
                      Icons.fitness_center_rounded,
                      size: 14,
                      color: ink,
                    ),
                    label: Text(
                      'chat.practiceThisAction'.tr(),
                      style: textTheme.bodySmall?.copyWith(color: ink),
                    ),
                    onPressed: onPractice,
                    backgroundColor: theme.colorScheme.surface,
                    side: BorderSide.none,
                    visualDensity: TapTargetBox.applies(context)
                        ? VisualDensity.standard
                        : VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CorrectionLine extends StatelessWidget {
  const _CorrectionLine({
    required this.icon,
    required this.iconColor,
    required this.child,
  });

  final IconData icon;
  final Color iconColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: child),
      ],
    );
  }
}

Widget _themedMd(BuildContext context, String text, TextStyle style) =>
    MarkdownMessageContent(
      content: text,
      isDark: Theme.of(context).brightness == Brightness.dark,
      selectable: false,
      baseTextStyle: style,
    );

/// Vocabulary Hint Card
/// Shows vocabulary definition and example
class VocabularyHintCard extends StatelessWidget {
  final VocabularyHint hint;
  final VoidCallback? onSave;
  final VoidCallback? onPracticePronunciation;

  const VocabularyHintCard({
    super.key,
    required this.hint,
    this.onSave,
    this.onPracticePronunciation,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with term
          Row(
            children: [
              Icon(Icons.book, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      hint.term,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    if (hint.partOfSpeech != null)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.sm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            hint.partOfSpeech!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: Colors.blue.shade800),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Pronunciation
              if (hint.pronunciation != null)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    hint.pronunciation!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.blue.shade600,
                    ),
                  ),
                ),
              if (onPracticePronunciation != null)
                InkWell(
                  onTap: onPracticePronunciation,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.mic_rounded,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              if (onSave != null)
                InkWell(
                  onTap: onSave,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.bookmark_add_outlined,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Definition
          _md(
            hint.definition,
            Theme.of(context).textTheme.bodySmall!.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),

          // Example
          if (hint.example != null && hint.example!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Container(
                padding: EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 14,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: _md(
                        hint.example!,
                        Theme.of(context).textTheme.bodySmall!.copyWith(
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Topic Progress Indicator
/// Shows progress in the current topic conversation
class TopicProgressIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String? stepLabel;

  const TopicProgressIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.stepLabel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalSteps > 0 ? currentStep / totalSteps : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stepLabel ?? 'Progress',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
              Text(
                '$currentStep / $totalSteps',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}

/// Expandable hints toggle
/// Small button to show/hide educational hints
class ExpandableHintsToggle extends StatefulWidget {
  final EducationalHints hints;

  const ExpandableHintsToggle({super.key, required this.hints});

  @override
  State<ExpandableHintsToggle> createState() => _ExpandableHintsToggleState();
}

class _ExpandableHintsToggleState extends State<ExpandableHintsToggle> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final totalHints =
        widget.hints.grammarCorrections.length +
        widget.hints.vocabularyHints.length;

    if (totalHints == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle button
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.school, size: 14, color: Colors.purple.shade600),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'chat.learningHintsCount'.plural(totalHints),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.purple.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.purple.shade600,
                ),
              ],
            ),
          ),
        ),

        // Expanded hints
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: EducationalHintsCard(hints: widget.hints),
          ),
      ],
    );
  }
}
