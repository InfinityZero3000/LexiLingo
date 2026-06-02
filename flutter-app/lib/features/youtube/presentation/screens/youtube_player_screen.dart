import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:lexilingo_app/core/widgets/quick_save_word_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/youtube_entities.dart';
import '../providers/youtube_provider.dart';

/// YouTube Player Screen — embedded player with synced subtitle panel.
///
/// Features:
/// - Embedded YouTube player (youtube_player_iframe)
/// - Live synced subtitle panel — highlights active caption
/// - Tap word → save to vocabulary
class YouTubePlayerScreen extends StatefulWidget {
  final YouTubeVideo video;

  const YouTubePlayerScreen({super.key, required this.video});

  @override
  State<YouTubePlayerScreen> createState() => _YouTubePlayerScreenState();
}

class _YouTubePlayerScreenState extends State<YouTubePlayerScreen>
    with SingleTickerProviderStateMixin {
  late final YoutubePlayerController _ytController;
  late final AnimationController _fadeController;
  final ScrollController _captionScrollController = ScrollController();

  // Tracks the current playback position in milliseconds for caption sync
  int _currentPositionMs = 0;
  Timer? _positionTimer;

  // Index of the currently active caption — used to auto-scroll the list
  int _activeCaptionIndex = -1;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    _ytController = YoutubePlayerController.fromVideoId(
      videoId: widget.video.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: false, // We display captions ourselves
        strictRelatedVideos: true,
        playsInline: true,
      ),
    );

    // Poll position every 500 ms for caption synchronisation
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _syncPosition();
    });

    // Load captions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YouTubeProvider>().loadCaptions(widget.video.videoId);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _ytController.close();
    _positionTimer?.cancel();
    _captionScrollController.dispose();
    super.dispose();
  }

  Future<void> _syncPosition() async {
    try {
      final seconds = await _ytController.currentTime;
      final posMs = (seconds * 1000).round();
      if (!mounted || posMs == _currentPositionMs) return;

      final provider = context.read<YouTubeProvider>();
      int newIndex = -1;
      for (int i = 0; i < provider.captions.length; i++) {
        if (provider.captions[i].isActiveAt(posMs)) {
          newIndex = i;
          break;
        }
      }

      setState(() {
        _currentPositionMs = posMs;
        _activeCaptionIndex = newIndex;
      });

      // Auto-scroll caption list to active segment
      if (newIndex >= 0 && _captionScrollController.hasClients) {
        const rowHeight = 56.0;
        final offset = (newIndex * rowHeight).clamp(
          0.0,
          _captionScrollController.position.maxScrollExtent,
        );
        _captionScrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (_) {
      // Player may not be ready yet
    }
  }

  void _onWordTap(String word, {String? contextSentence}) {
    final cleanWord = word.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();
    if (cleanWord.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _buildDictionarySheet(cleanWord, contextSentence: contextSentence),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeController,
          child: Column(
            children: [
              // ── Embedded Player ──
              _buildPlayerArea(isDark),

              // ── Content below player ──
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.backgroundDark
                        : AppColors.backgroundLight,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildVideoInfo(isDark),
                        const SizedBox(height: 20),
                        _buildCaptionPanel(isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Player Area
  // ──────────────────────────────────────

  Widget _buildPlayerArea(bool isDark) {
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: YoutubePlayer(controller: _ytController),
          ),
        ),
        // Back button overlay
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────
  //  Video Info
  // ──────────────────────────────────────

  Widget _buildVideoInfo(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.video.title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        if (widget.video.cefrLevel.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _cefrColor(widget.video.cefrLevel),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.video.cefrLevel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.video.channelTitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  if (widget.video.publishedAt.isNotEmpty)
                    Text(
                      _formatDate(widget.video.publishedAt),
                      style: TextStyle(
                        color: isDark ? Colors.white54 : AppColors.textGrey,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────
  //  Caption / Subtitle Panel
  // ──────────────────────────────────────

  Widget _buildCaptionPanel(bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingCaptions) {
          return _captionContainer(
            isDark,
            child: const Center(child: LottieLoadingWidget.medium()),
          );
        }

        if (provider.captions.isEmpty) {
          return _captionContainer(
            isDark,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.subtitles_off_rounded,
                  size: 40,
                  color: isDark ? Colors.white30 : AppColors.grey400,
                ),
                const SizedBox(height: 8),
                Text(
                  'youtube.noSubtitles'.tr(),
                  style: TextStyle(
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                const Icon(
                  Icons.subtitles_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'youtube.subtitles'.tr(),
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '${provider.captions.length} segments',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : AppColors.textGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Caption list (fixed height, internally scrollable)
            Container(
              constraints: const BoxConstraints(maxHeight: 320),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppColors.grey200,
                ),
              ),
              child: ListView.separated(
                controller: _captionScrollController,
                padding: const EdgeInsets.all(12),
                itemCount: provider.captions.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : AppColors.grey200,
                ),
                itemBuilder: (context, index) {
                  final segment = provider.captions[index];
                  final isActive = index == _activeCaptionIndex;
                  return _buildCaptionRow(
                    segment,
                    isDark,
                    isActive: isActive,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _captionContainer(bool isDark, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : AppColors.grey200,
        ),
      ),
      child: child,
    );
  }

  Widget _buildCaptionRow(
    CaptionSegment segment,
    bool isDark, {
    required bool isActive,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp — tap to seek
          GestureDetector(
            onTap: () {
              _ytController.seekTo(
                seconds: segment.startMs / 1000,
                allowSeekAhead: true,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _formatTimestamp(segment.startMs),
                style: TextStyle(
                  color: isActive
                      ? AppColors.primary
                      : (isDark ? Colors.white38 : AppColors.textGrey),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Caption text — tap each word for dictionary
          Expanded(
            child: Wrap(
              spacing: 3,
              runSpacing: 2,
              children: segment.text.split(' ').map((word) {
                return GestureDetector(
                  onTap: () =>
                      _onWordTap(word, contextSentence: segment.text),
                  child: Text(
                    word,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? (isDark ? Colors.white : AppColors.textDark)
                          : (isDark
                                ? Colors.white70
                                : AppColors.textDark.withValues(alpha: 0.7)),
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.transparent,
                      decorationStyle: TextDecorationStyle.dotted,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Dictionary Bottom Sheet
  // ──────────────────────────────────────

  Widget _buildDictionarySheet(String word, {String? contextSentence}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey400,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            word,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'youtube.dictionaryComingSoon'.tr(),
            style: TextStyle(fontSize: 14, color: AppColors.textGrey),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Future.microtask(() {
                      if (!mounted) return;
                      showQuickSaveWordSheet(
                        context,
                        word: word,
                        sourceType: 'youtube',
                        sourceReference: widget.video.videoId,
                        contextSentence: contextSentence,
                      );
                    });
                  },
                  icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text('youtube.saveWord'.tr()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: Text('common.close'.tr()),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  String _formatTimestamp(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final diff = DateTime.now().difference(date);
      if (diff.inDays == 0) return 'datetime.today'.tr();
      if (diff.inDays == 1) return 'datetime.yesterday'.tr();
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
      if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo ago';
      return '${diff.inDays ~/ 365}y ago';
    } catch (_) {
      return '';
    }
  }

  Color _cefrColor(String level) {
    switch (level) {
      case 'A1':
        return AppColors.greenSuccessBright;
      case 'A2':
        return AppColors.greenSuccessSoft;
      case 'B1':
        return AppColors.warning;
      case 'B2':
        return AppColors.orange;
      case 'C1':
        return AppColors.deepOrange;
      case 'C2':
        return AppColors.purple;
      default:
        return AppColors.primary;
    }
  }
}
