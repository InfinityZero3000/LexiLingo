import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shimmer/shimmer.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/widgets/content_kit.dart';
import '../../../../core/widgets/quick_save_selection_area.dart';

/// Scrollable transcript panel shown inside the podcast player.
///
/// States:
/// - `isLoading == true`:  shimmer skeleton
/// - `transcript != null`: scrollable paragraph blocks
/// - otherwise:            "No transcript" placeholder with optional generate button
///
/// Phase 4: Podcast.
class TranscriptPanel extends StatelessWidget {
  final String? transcript;
  final bool isLoading;
  final VoidCallback? onGenerateTranscript;
  final String? sourceReference;

  /// Off when the screen already titles the section above this panel.
  final bool showHeading;

  const TranscriptPanel({
    super.key,
    this.transcript,
    required this.isLoading,
    this.onGenerateTranscript,
    this.sourceReference,
    this.showHeading = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 120),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeading) ...[
                Row(
                  children: [
                    Icon(
                      PhosphorIconsBold.subtitles,
                      size: 20,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'podcast.transcriptLabel'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // ── Content area ──
              if (isLoading)
                _buildShimmer(context)
              else if (transcript != null && transcript!.isNotEmpty)
                _buildTranscript(context, transcript!)
              else
                _buildEmpty(context),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Loading shimmer
  // ──────────────────────────────────────

  Widget _buildShimmer(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.onSurface.withValues(alpha: 0.08),
      highlightColor: scheme.onSurface.withValues(alpha: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FractionallySizedBox(
                widthFactor: i % 3 == 2 ? 0.6 : 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const SizedBox(height: 14, width: double.infinity),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Transcript paragraphs
  // ──────────────────────────────────────

  Widget _buildTranscript(BuildContext context, String text) {
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final para in paragraphs) _buildParagraph(context, para)],
    );
  }

  Widget _buildParagraph(BuildContext context, String para) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            child: QuickSaveSelectionArea(
              sourceType: 'podcast',
              sourceReference: sourceReference,
              contextSentence: para,
              child: Text(
                para,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Empty state
  // ──────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          Icon(
            PhosphorIconsBold.subtitles,
            size: 48,
            color: scheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 10),
          Text(
            'podcast.noTranscript'.tr(),
            style: TextStyle(fontSize: 14, color: contentMuted(context)),
            textAlign: TextAlign.center,
          ),
          if (onGenerateTranscript != null) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onGenerateTranscript,
              icon: const Icon(PhosphorIconsBold.sparkle, size: 18),
              label: Text('podcast.generateTranscript'.tr()),
              style: FilledButton.styleFrom(
                minimumSize: const Size(44, 44),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
