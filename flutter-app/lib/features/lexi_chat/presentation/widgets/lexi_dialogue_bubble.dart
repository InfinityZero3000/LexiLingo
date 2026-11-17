import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/quick_save_selection_area.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/markdown_message_content.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_course_suggestions.dart';
import 'package:lexilingo_app/features/voice/domain/entities/pronunciation_score.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/pronunciation_score_card.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Minimalist dialogue bubble for Lexi chat.
///
/// Clean, simple design without avatars:
///  - Lexi (left-aligned): Simple text bubble with subtle styling
///  - User (right-aligned): Clean colored bubble
class LexiDialogueBubble extends StatelessWidget {
  final LexiMessage message;
  final VoidCallback? onPlayAudio;
  final VoidCallback? onShowCorrections;
  final VoidCallback? onPronunciationScoreTap;
  final ValueChanged<LexiSuggestedPractice>? onSuggestedPracticeTap;
  final String? lexiAvatarUrl;

  /// Listening-practice mode: a voice reply stays covered until tapped.
  final bool captionHidden;
  final VoidCallback? onRevealCaption;
  final VoidCallback? onMisheardTap;

  const LexiDialogueBubble({
    super.key,
    required this.message,
    this.onPlayAudio,
    this.onShowCorrections,
    this.onPronunciationScoreTap,
    this.onSuggestedPracticeTap,
    this.lexiAvatarUrl,
    this.captionHidden = false,
    this.onRevealCaption,
    this.onMisheardTap,
  });

  @override
  Widget build(BuildContext context) {
    return message.isLexi
        ? _buildLexiBubble(context)
        : _buildUserBubble(context);
  }

  Widget _buildLexiBubble(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sender label
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'lexiChat.title'.tr(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? Colors.white54
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
              ),
              if (message.hasCorrections) ...[
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: context.status.warning.withValues(
                      alpha: isDark ? 0.2 : 0.15,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_fix_high_rounded,
                        size: 10,
                        color: context.status.warning,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'lexiChat.correctionLabel'.tr(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: context.status.warning,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Message bubble
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.backgroundLight,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: Border.all(
              color: isDark ? AppColors.surfaceDarkChat : AppColors.chatBgLight,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Message text
              if (captionHidden)
                _buildHiddenCaption(context, isDark)
              else
                _buildLexiMessageContent(context, isDark),
              // Real catalog rows, attached by the server when the learner
              // asked what to study — see LexiCourseSuggestions.
              LexiCourseSuggestions(courses: message.suggestedCourses),
              // Action buttons row
              if (message.hasAudio ||
                  onShowCorrections != null ||
                  message.suggestedPractice != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (message.hasAudio)
                        _buildActionChip(
                          context,
                          icon: Icons.volume_up_rounded,
                          label: 'lexiChat.listenButton'.tr(),
                          onTap: onPlayAudio,
                        ),
                      if (onShowCorrections != null)
                        _buildActionChip(
                          context,
                          icon: Icons.auto_fix_high_rounded,
                          label: 'lexiChat.viewNotesButton'.tr(),
                          onTap: onShowCorrections,
                          color: context.status.warning,
                        ),
                      if (message.suggestedPractice != null &&
                          onSuggestedPracticeTap != null)
                        _buildActionChip(
                          context,
                          icon: Icons.fitness_center_rounded,
                          label: 'lexiChat.practiceMoreButton'.tr(
                            namedArgs: {
                              'concept':
                                  message.suggestedPractice!.conceptTitle,
                            },
                          ),
                          onTap: () => onSuggestedPracticeTap!(
                            message.suggestedPractice!,
                          ),
                          color: AppColors.accentMint,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHiddenCaption(BuildContext context, bool isDark) {
    final color = isDark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: 'lexiChat.voice.tapToReveal'.tr(),
      child: InkWell(
        onTap: onRevealCaption,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_rounded, size: 18, color: color),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'lexiChat.voice.tapToReveal'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(height: 1.5, color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLexiMessageContent(BuildContext context, bool isDark) {
    final baseTextStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      height: 1.5,
      color: isDark
          ? AppColors.onGradient
          : Theme.of(context).colorScheme.onSurface,
      letterSpacing: -0.1,
    );

    final highlightColor = isDark
        ? context.status.warning.withValues(alpha: 0.25)
        : context.status.warning.withValues(alpha: 0.2);

    return QuickSaveSelectionArea(
      sourceType: 'lexi_chat',
      sourceReference: message.id,
      contextSentence: message.content,
      child: MarkdownMessageContent(
        content: message.content,
        isDark: isDark,
        selectable: false,
        baseTextStyle: baseTextStyle,
        highlightColor: highlightColor,
        saveSourceType: 'lexi_chat',
        saveSourceReference: message.id,
      ),
    );
  }

  Widget _buildUserBubble(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: AppColorRoles.primary(isDark),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: QuickSaveSelectionArea(
            sourceType: 'lexi_chat',
            sourceReference: message.id,
            contextSentence: message.content,
            child: _buildUserMessageContent(context),
          ),
        ),
        if (message.isPendingSync)
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 12,
                  color: isDark
                      ? Colors.white60
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    'lexiChat.pendingSync'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? Colors.white60
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        if (message.heardUncertain && onMisheardTap != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _buildActionChip(
              context,
              icon: Icons.hearing_disabled_rounded,
              label: 'lexiChat.voice.misheardChip'.tr(),
              onTap: onMisheardTap,
              color: context.status.warning,
              labelColor: isDark
                  ? AppColors.onGradient
                  : AppColors.textDark,
            ),
          ),
        if (message.pronunciationScore != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _PronunciationScoreChip(
              score: message.pronunciationScore!,
              onTap: onPronunciationScoreTap,
            ),
          ),
      ],
    );
  }

  /// The plain-text fast path when there's nothing to correct; otherwise
  /// the mistake is struck through right where the user typed it, tappable
  /// to open the same corrections sheet as the "View notes" chip.
  Widget _buildUserMessageContent(BuildContext context) {
    final baseStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      height: 1.5,
      color: Theme.of(context).colorScheme.surface,
      letterSpacing: -0.1,
    );

    if (message.corrections.isEmpty) {
      return Text(message.content, style: baseStyle);
    }

    return Text.rich(
      TextSpan(style: baseStyle, children: _buildCorrectedSpans(baseStyle)),
    );
  }

  List<InlineSpan> _buildCorrectedSpans(TextStyle baseStyle) {
    final content = message.content;

    // First non-overlapping occurrence of each correction's errorSpan —
    // errorSpan is a literal substring of what the user typed (unlike
    // Lexi's own generated reply, which may not repeat it verbatim), so
    // plain case-insensitive substring search is reliable here.
    final matches = <(int start, int end, LexiCorrection correction)>[];
    for (final correction in message.corrections) {
      final errorSpan = correction.errorSpan.trim();
      if (errorSpan.isEmpty) continue;
      final start = content.toLowerCase().indexOf(errorSpan.toLowerCase());
      if (start == -1) continue;
      final end = start + errorSpan.length;
      final overlaps = matches.any((m) => start < m.$2 && end > m.$1);
      if (!overlaps) matches.add((start, end, correction));
    }

    if (matches.isEmpty) return [TextSpan(text: content)];
    matches.sort((a, b) => a.$1.compareTo(b.$1));

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final (start, end, _) in matches) {
      if (start > cursor) {
        spans.add(TextSpan(text: content.substring(cursor, start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: onShowCorrections,
            child: Text(
              content.substring(start, end),
              style: baseStyle.copyWith(
                decoration: TextDecoration.lineThrough,
                decorationColor: AppColors.errorBright,
                decorationThickness: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < content.length) {
      spans.add(TextSpan(text: content.substring(cursor)));
    }
    return spans;
  }

  Widget _buildActionChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    Color? color,
    Color? labelColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipColor = color ?? AppColorRoles.primary(isDark);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: chipColor.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: chipColor.withValues(alpha: isDark ? 0.3 : 0.2),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: chipColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: labelColor ?? chipColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact score pill under a voice message — tap to see the full
/// [PronunciationScoreCard] breakdown in a sheet, without letting the big
/// card dominate the chat feed on every voice turn.
class _PronunciationScoreChip extends StatelessWidget {
  final PronunciationScore score;
  final VoidCallback? onTap;

  const _PronunciationScoreChip({required this.score, this.onTap});

  Color _scoreColor() {
    if (score.overallScore >= 90) return AppColors.greenSuccessBright;
    if (score.overallScore >= 70) return AppColors.warning;
    if (score.overallScore >= 50) return AppColors.orange;
    return AppColors.errorBright;
  }

  void _showDetails(BuildContext context) {
    onTap?.call();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SafeArea(
          child: SingleChildScrollView(
            child: PronunciationScoreCard(score: score),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor();

    return InkWell(
      onTap: () => _showDetails(context),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_rounded, size: 12, color: color),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                'lexiChat.pronunciationScoreLabel'.tr(
                  namedArgs: {'score': '${score.overallScore}'},
                ),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
