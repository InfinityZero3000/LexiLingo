import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/theme/app_theme.dart';

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

  const TranscriptPanel({
    super.key,
    this.transcript,
    required this.isLoading,
    this.onGenerateTranscript,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section heading ──
          Row(
            children: [
              const Icon(Icons.subtitles_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Transcript',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Content area ──
          if (isLoading)
            _buildShimmer(isDark)
          else if (transcript != null && transcript!.isNotEmpty)
            _buildTranscript(transcript!, isDark)
          else
            _buildEmpty(context, isDark),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Loading shimmer
  // ──────────────────────────────────────

  Widget _buildShimmer(bool isDark) {
    final baseColor =
        isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.shade200;
    final highlightColor =
        isDark ? Colors.white.withValues(alpha: 0.15) : Colors.grey.shade100;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(5, (i) {
          final isShort = i % 3 == 2;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 14,
              width: isShort ? double.infinity * 0.6 : double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Transcript paragraphs
  // ──────────────────────────────────────

  Widget _buildTranscript(String text, bool isDark) {
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paragraphs
          .map(
            (para) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : AppColors.grey200,
                  ),
                ),
                child: Text(
                  para,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: isDark ? Colors.white.withOpacity(0.87) : AppColors.textDark,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ──────────────────────────────────────
  //  Empty state
  // ──────────────────────────────────────

  Widget _buildEmpty(BuildContext context, bool isDark) {
    return Column(
      children: [
        Icon(
          Icons.subtitles_off_rounded,
          size: 48,
          color: isDark ? Colors.white24 : Colors.grey.shade300,
        ),
        const SizedBox(height: 10),
        Text(
          'No transcript available',
          style: TextStyle(
            color: isDark ? Colors.white38 : AppColors.textGrey,
            fontSize: 14,
          ),
          textAlign: TextAlign.center,
        ),
        if (onGenerateTranscript != null) ...[
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onGenerateTranscript,
            icon: const Icon(Icons.auto_awesome_rounded, size: 16),
            label: const Text('Generate Transcript'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
