import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/chat/presentation/helpers/chat_mistake_recorder.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';

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
    await const ChatMistakeRecorder().recordGrammarCorrection(
      sourceType: 'lexi_chat',
      sourceId: messageId,
      original: c.errorSpan,
      corrected: c.correction,
      explanation: c.explanation,
      skill: c.errorType,
    );
    if (!context.mounted) return;
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
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(top: 16, bottom: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white24
                  : Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentYellow.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_fix_high_rounded,
                    size: 18,
                    color: AppColors.accentYellow,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'lexiChat.languageNotes'.tr(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : AppColors.textDark,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Content
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(20),
              shrinkWrap: true,
              children: [
                // Corrections
                if (corrections.isNotEmpty) ...[
                  _sectionTitle(context, 'lexiChat.correctionsSection'.tr()),
                  const SizedBox(height: 12),
                  ...corrections.map((c) => _correctionCard(context, c)),
                  const SizedBox(height: 16),
                ],
                if (nativeHint != null) ...[
                  _sectionTitle(context, 'lexiChat.nativeHintSection'.tr()),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.surfaceDarkCard
                          : AppColors.surfaceWarmSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark
                            ? AppColors.surfaceDarkChat
                            : AppColors.accentYellow.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 18,
                          color: AppColors.accentYellow,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            nativeHint!,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Linked concepts
                if (linkedConcepts.isNotEmpty) ...[
                  _sectionTitle(
                    context,
                    'lexiChat.relatedConceptsSection'.tr(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'lexiChat.relatedConceptsHint'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: isDark ? Colors.white54 : AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 12),
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
        return const Color(0xFF3B82F6);
      case 'function':
        return const Color(0xFF8B5CF6);
      case 'conversation':
        return const Color(0xFF10B981);
      case 'error':
        return const Color(0xFFEF4444);
      case 'vocab':
      case 'phrase':
      case 'collocation':
        return const Color(0xFFF59E0B);
      case 'phonology':
        return const Color(0xFF06B6D4);
      default:
        return AppColors.primary;
    }
  }

  Widget _overflowChip(BuildContext context, int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.grey.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Text(
        '+$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white54 : AppColors.textGrey,
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
        color: color.withValues(alpha: isDark ? 0.12 : 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.35 : 0.22),
          width: 1,
        ),
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.75),
                letterSpacing: 0.2,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                '·',
                style: TextStyle(
                  fontSize: 12,
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
              style: TextStyle(
                fontSize: 13,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : AppColors.textGrey,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _correctionCard(BuildContext context, LexiCorrection correction) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget correctionChip({
      required String text,
      required Color textColor,
      required Color backgroundColor,
      required Color borderColor,
      bool strikeThrough = false,
      FontWeight fontWeight = FontWeight.w500,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontSize: 13,
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
        color: isDark ? AppColors.surfaceDarkCard : AppColors.surfaceWarm,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? AppColors.accentYellow.withValues(alpha: 0.2)
              : AppColors.accentYellow.withValues(alpha: 0.3),
          width: 1,
        ),
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
                  textColor: AppColors.errorBright,
                  backgroundColor: Colors.red.withValues(alpha: 0.08),
                  borderColor: Colors.red.withValues(alpha: 0.15),
                  strikeThrough: true,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              // Correction
              Expanded(
                child: correctionChip(
                  text: correction.correction,
                  textColor: AppColors.greenSuccess,
                  backgroundColor: AppColors.greenSuccess.withValues(
                    alpha: 0.08,
                  ),
                  borderColor: AppColors.greenSuccess.withValues(alpha: 0.2),
                  fontWeight: FontWeight.w600,
                ),
              ),
              InkWell(
                onTap: () => _saveMistake(context, correction),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 2),
                  child: Icon(
                    Icons.bookmark_add_outlined,
                    size: 18,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
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
                color: isDark ? AppColors.surfaceDarkInk : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      correction.explanation,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: isDark ? Colors.white70 : AppColors.textGrey,
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
