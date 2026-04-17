import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';

/// Minimalist bottom sheet showing grammar/vocabulary corrections from Lexi.
class LexiCorrectionsSheet extends StatelessWidget {
  final List<LexiCorrection> corrections;
  final String? vietnameseHint;
  final List<String> linkedConcepts;

  const LexiCorrectionsSheet({
    super.key,
    required this.corrections,
    this.vietnameseHint,
    this.linkedConcepts = const [],
  });

  static void show(BuildContext context, LexiMessage message) {
    if (!message.hasCorrections &&
        message.vietnameseHint == null &&
        message.linkedConcepts.isEmpty) {
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LexiCorrectionsSheet(
        corrections: message.corrections,
        vietnameseHint: message.vietnameseHint,
        linkedConcepts: message.linkedConcepts,
      ),
    );
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
                  'Language Notes',
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
                  _sectionTitle(context, 'Corrections'),
                  const SizedBox(height: 12),
                  ...corrections.map((c) => _correctionCard(context, c)),
                  const SizedBox(height: 16),
                ],
                // Vietnamese hint
                if (vietnameseHint != null) ...[
                  _sectionTitle(context, 'Vietnamese Hint'),
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
                            vietnameseHint!,
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
                  _sectionTitle(context, 'Related Concepts'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: linkedConcepts
                        .map(
                          (c) => Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width - 88,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.surfaceDarkChat
                                  : AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? AppColors.borderDarkSoft
                                    : AppColors.primary.withValues(alpha: 0.2),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              c,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white70
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
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
