import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/chat/presentation/helpers/chat_mistake_recorder.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Minimalist bottom sheet showing grammar/vocabulary corrections from Lexi.
class LexiCorrectionsSheet extends StatelessWidget {
  final List<LexiCorrection> corrections;
  final String? nativeHint;
  final List<String> linkedConcepts;
  final Map<String, String> conceptLabels;
  final String messageId;

  const LexiCorrectionsSheet({
    super.key,
    required this.corrections,
    required this.messageId,
    this.nativeHint,
    this.linkedConcepts = const [],
    this.conceptLabels = const {},
  });

  static void show(BuildContext context, LexiMessage message) {
    if (!message.hasCorrections &&
        message.nativeHint == null &&
        message.linkedConcepts.isEmpty) {
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LexiCorrectionsSheet(
        corrections: message.corrections,
        messageId: message.id,
        nativeHint: message.nativeHint,
        linkedConcepts: message.linkedConcepts,
        conceptLabels: message.conceptLabels,
      ),
    );
  }

  Future<void> _saveMistake(BuildContext context, LexiCorrection c) async {
    final saved = await const ChatMistakeRecorder().recordGrammarCorrection(
      sourceType: 'lexi_chat',
      sourceId: messageId,
      original: c.errorSpan,
      corrected: c.correction,
      explanation: c.explanation,
      errorType: c.errorType,
    );
    if (!saved || !context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('lexiChat.savedToMistakes'.tr())));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(
              top: AppSpacing.lg,
              bottom: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: context.status.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(
                    Icons.auto_fix_high_rounded,
                    size: 18,
                    color: context.status.warning,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  'lexiChat.languageNotes'.tr(),
                  style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Content
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(20),
              shrinkWrap: true,
              children: [
                // Corrections
                if (corrections.isNotEmpty) ...[
                  _sectionTitle(context, 'lexiChat.correctionsSection'.tr()),
                  const SizedBox(height: AppSpacing.md),
                  ...corrections.map((c) => _correctionCard(context, c)),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (nativeHint != null) ...[
                  _sectionTitle(context, 'lexiChat.nativeHintSection'.tr()),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: context.status.warning.withValues(
                        alpha: isDark ? 0.14 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 18,
                          color: context.status.warning,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            nativeHint!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  height: 1.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                // Linked concepts
                if (linkedConcepts.isNotEmpty) ...[
                  _sectionTitle(
                    context,
                    'lexiChat.relatedConceptsSection'.tr(),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'lexiChat.relatedConceptsHint'.tr(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.4,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Builder(
                    builder: (ctx) {
                      const maxVisible = 8;
                      final concepts = describeConcepts(
                        linkedConcepts,
                        conceptLabels,
                      );
                      final visible = concepts.take(maxVisible).toList();
                      final overflow = concepts.length - maxVisible;
                      return Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...visible.map((c) => _conceptChip(context, c)),
                          if (overflow > 0) _overflowChip(context, overflow),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _categoryColor(String category) {
    switch (category) {
      case 'grammar':
      case 'usage':
        return AppColors.primary;
      case 'function':
        return AppColors.purple;
      case 'conversation':
        return AppColors.greenSuccess;
      case 'error':
        return AppColors.errorBright;
      case 'vocab':
      case 'phrase':
      case 'collocation':
        return AppColors.orange;
      case 'phonology':
        return AppColors.teal;
      default:
        return AppColors.primary;
    }
  }

  Widget _overflowChip(BuildContext context, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        '+$count',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _conceptChip(BuildContext context, ConceptChip concept) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _categoryColor(concept.kind);
    final catLabel = concept.categoryLabel;
    final label = concept.label;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          if (catLabel.isNotEmpty) ...[
            Text(
              catLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.75),
                letterSpacing: 0.2,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                '·',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: isDark ? color.withValues(alpha: 0.9) : color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _correctionCard(BuildContext context, LexiCorrection correction) {
    Widget correctionChip({
      required String text,
      required Color textColor,
      required Color backgroundColor,
      bool strikeThrough = false,
      FontWeight fontWeight = FontWeight.w500,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: textColor,
            fontWeight: fontWeight,
            decoration: strikeThrough ? TextDecoration.lineThrough : null,
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error → Correction
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: correctionChip(
                  text: correction.errorSpan,
                  textColor: Theme.of(context).colorScheme.onErrorContainer,
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  strikeThrough: true,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              // Correction
              Expanded(
                child: correctionChip(
                  text: correction.correction,
                  textColor: context.status.onSuccessContainer,
                  backgroundColor: context.status.successContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Semantics(
                button: true,
                label: 'chat.saveCorrection'.tr(),
                child: InkWell(
                  onTap: () => _saveMistake(context, correction),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.bookmark_add_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (correction.explanation.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      correction.explanation,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One "Related Concepts" chip, ready to render.
class ConceptChip {
  final String kind;
  final String categoryLabel;
  final String label;
  const ConceptChip(this.kind, this.categoryLabel, this.label);
}

const _kindLabelKeys = {
  'grammar': 'lexiChat.conceptGrammar',
  'usage': 'lexiChat.conceptUsage',
  'function': 'lexiChat.conceptFunction',
  'conversation': 'lexiChat.conceptConversation',
  'error': 'lexiChat.conceptError',
  'vocab': 'lexiChat.conceptVocab',
  'phrase': 'lexiChat.conceptPhrase',
  'collocation': 'lexiChat.conceptCollocation',
  'phonology': 'lexiChat.conceptPhonology',
  'skill': 'lexiChat.conceptSkill',
};

final _trailingHash = RegExp(r'-[0-9a-f]{10}$');

String _titleCase(String s) => s
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Chips for ids such as "concept:grammar.some-slug-hash" or "grammar:story_x_y".
/// The server title wins; the slug is only a fallback for older saved messages.
/// Chips with no readable label are dropped and duplicates collapsed.
List<ConceptChip> describeConcepts(
  List<String> ids,
  Map<String, String> titles,
) {
  final seen = <String>{};
  final chips = <ConceptChip>[];
  for (final id in ids) {
    final raw = id.trim().replaceFirst('concept:', '');
    final cut = raw.indexOf(RegExp(r'[.:]'));
    if (cut < 0) continue;
    var kind = raw.substring(0, cut);
    var slug = raw.substring(cut + 1);
    final hashed = _trailingHash.hasMatch(slug);
    // 09_grammar_usage: learner Q&A, not a grammar rule.
    if (kind == 'grammar' && hashed) kind = 'usage';
    slug = slug
        .replaceFirst(_trailingHash, '')
        .replaceFirst(RegExp(r'^(word\.|story_)'), '');
    final label = titles[id]?.trim().isNotEmpty == true
        ? titles[id]!.trim()
        : _titleCase(slug.replaceAll(RegExp(r'[_\-.]+'), ' ').trim());
    if (label.isEmpty || !seen.add('$kind|$label')) continue;
    final key = _kindLabelKeys[kind];
    chips.add(
      ConceptChip(kind, key != null ? key.tr() : _titleCase(kind), label),
    );
  }
  return chips;
}
