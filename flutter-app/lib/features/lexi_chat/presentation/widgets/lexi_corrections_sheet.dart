import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';

/// Bottom sheet showing grammar/vocabulary corrections from Lexi.
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
        message.linkedConcepts.isEmpty)
      return;

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
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('🦜', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Text(
                  'Lexi\'s Notes',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Content
          Flexible(
            child: ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                // Corrections
                if (corrections.isNotEmpty) ...[
                  _sectionTitle(context, '✏️ Corrections'),
                  const SizedBox(height: 8),
                  ...corrections.map((c) => _correctionCard(context, c)),
                  const SizedBox(height: 16),
                ],
                // Vietnamese hint
                if (vietnameseHint != null) ...[
                  _sectionTitle(context, '🇻🇳 Vietnamese Hint'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A2E3F)
                          : const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      vietnameseHint!,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Linked concepts
                if (linkedConcepts.isNotEmpty) ...[
                  _sectionTitle(context, '🔗 Related Concepts'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: linkedConcepts
                        .map(
                          (c) => Chip(
                            label: Text(
                              c,
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: isDark
                                ? const Color(0xFF2A3A4A)
                                : AppColors.primary.withValues(alpha: 0.1),
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
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white70 : AppColors.textGrey,
      ),
    );
  }

  Widget _correctionCard(BuildContext context, LexiCorrection correction) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2E3F) : const Color(0xFFFFF8F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? AppColors.accentYellow.withValues(alpha: 0.3)
              : AppColors.accentYellow.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Error → Correction
          Row(
            children: [
              // Error
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  correction.errorSpan,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 16),
              ),
              // Correction
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.greenSuccess.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  correction.correction,
                  style: const TextStyle(
                    color: AppColors.greenSuccess,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (correction.explanation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              correction.explanation,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : AppColors.textGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
