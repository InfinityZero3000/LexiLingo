import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:lexilingo_app/core/widgets/quick_save_word_sheet.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/youtube_entities.dart';
import '../providers/youtube_provider.dart';

/// YouTube Player Screen — player + subtitles with tap-to-translate,
/// save video, speed control, and translation history.
class YouTubePlayerScreen extends StatefulWidget {
  final YouTubeVideo video;

  const YouTubePlayerScreen({super.key, required this.video});

  @override
  State<YouTubePlayerScreen> createState() => _YouTubePlayerScreenState();
}

class _YouTubePlayerScreenState extends State<YouTubePlayerScreen>
    with TickerProviderStateMixin {
  late final YoutubePlayerController _ytController;
  late final AnimationController _fadeController;
  late final TabController _tabController;
  final ScrollController _captionScrollController = ScrollController();

  int _currentPositionMs = 0;
  Timer? _positionTimer;
  int _activeCaptionIndex = -1;
  double _playbackSpeed = 1.0;

  static const _kSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();

    _tabController = TabController(length: 2, vsync: this);

    _ytController = YoutubePlayerController.fromVideoId(
      videoId: widget.video.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: false,
        strictRelatedVideos: true,
        playsInline: true,
      ),
    );

    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _syncPosition();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<YouTubeProvider>().loadCaptions(widget.video.videoId);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _tabController.dispose();
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

      if (newIndex >= 0 && _captionScrollController.hasClients) {
        const rowHeight = 60.0;
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
    } catch (_) {}
  }

  void _onWordTap(String word, {String? contextSentence}) {
    final cleanWord =
        word.replaceAll(RegExp(r"[^\w\s'-]"), '').trim().toLowerCase();
    if (cleanWord.isEmpty) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WordTranslationSheet(
        word: cleanWord,
        contextSentence: contextSentence,
        videoId: widget.video.videoId,
        provider: context.read<YouTubeProvider>(),
      ),
    );
  }

  void _showSpeedSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Tốc độ phát',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kSpeeds.map((speed) {
                final isSelected = speed == _playbackSpeed;
                return GestureDetector(
                  onTap: () {
                    _ytController.setPlaybackRate(speed);
                    setState(() => _playbackSpeed = speed);
                    Navigator.pop(context);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : AppColors.grey100),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : AppColors.grey200),
                      ),
                    ),
                    child: Text(
                      speed == 1.0 ? 'Bình thường' : '${speed}x',
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : AppColors.textDark),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : const Color(0xFFF7F8FC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeController,
          child: Column(
            children: [
              _buildPlayerArea(isDark),
              _buildInfoBar(isDark),
              _buildActionBar(isDark),
              _buildTabBar(isDark),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildCaptionsTab(isDark),
                    _buildVocabTab(isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Player
  // ─────────────────────────────────────────────

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
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  Info Bar (title + channel)
  // ─────────────────────────────────────────────

  Widget _buildInfoBar(bool isDark) {
    return Container(
      color: isDark ? AppColors.backgroundDark : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel avatar
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_rounded,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      widget.video.channelTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : AppColors.textGrey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (widget.video.cefrLevel.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _cefrColor(widget.video.cefrLevel),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.video.cefrLevel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Action Bar (Save / Speed / Share / Open)
  // ─────────────────────────────────────────────

  Widget _buildActionBar(bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        final isSaved = provider.isVideoSaved(widget.video.videoId);

        return Container(
          color: isDark ? AppColors.backgroundDark : Colors.white,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
          child: Row(
            children: [
              _ActionButton(
                icon: isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: isSaved ? 'Đã lưu' : 'Lưu video',
                color: isSaved ? AppColors.primary : null,
                isDark: isDark,
                onTap: () {
                  if (isSaved) {
                    provider.unsaveVideo(widget.video.videoId);
                    _showSnack('Đã xóa khỏi danh sách lưu');
                  } else {
                    provider.saveVideo(widget.video);
                    _showSnack('Đã lưu video');
                  }
                },
              ),
              _ActionButton(
                icon: Icons.speed_rounded,
                label: _playbackSpeed == 1.0
                    ? 'Tốc độ'
                    : '${_playbackSpeed}x',
                isDark: isDark,
                color: _playbackSpeed != 1.0 ? AppColors.primary : null,
                onTap: _showSpeedSheet,
              ),
              _ActionButton(
                icon: Icons.open_in_new_rounded,
                label: 'YouTube',
                isDark: isDark,
                onTap: () async {
                  final url = Uri.parse(
                      'https://www.youtube.com/watch?v=${widget.video.videoId}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
              Consumer<YouTubeProvider>(
                builder: (context, prov, _) {
                  final histCount =
                      prov.translationHistoryFor(widget.video.videoId).length;
                  return _ActionButton(
                    icon: Icons.history_edu_rounded,
                    label: histCount > 0 ? '$histCount từ' : 'Từ vựng',
                    isDark: isDark,
                    color: histCount > 0 ? AppColors.primary : null,
                    onTap: () => _tabController.animateTo(1),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  Tab Bar
  // ─────────────────────────────────────────────

  Widget _buildTabBar(bool isDark) {
    return Container(
      color: isDark ? AppColors.backgroundDark : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              labelColor: Colors.white,
              unselectedLabelColor:
                  isDark ? Colors.white54 : AppColors.textGrey,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Phụ đề'),
                Tab(text: 'Từ đã tra'),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Captions Tab
  // ─────────────────────────────────────────────

  Widget _buildCaptionsTab(bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingCaptions) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.captions.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.subtitles_off_rounded,
                    size: 52,
                    color: isDark ? Colors.white24 : AppColors.grey300),
                const SizedBox(height: 10),
                Text(
                  'youtube.noSubtitles'.tr(),
                  style: TextStyle(
                    color: isDark ? Colors.white38 : AppColors.textGrey,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Video này không có phụ đề tự động',
                  style: TextStyle(
                    color: isDark ? Colors.white24 : AppColors.grey400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  const Icon(Icons.subtitles_rounded,
                      size: 15, color: AppColors.primary),
                  const SizedBox(width: 5),
                  Text(
                    '${provider.captions.length} đoạn',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white38 : AppColors.textGrey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Nhấn vào từ để tra nghĩa',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white30 : AppColors.grey400,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _captionScrollController,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                itemCount: provider.captions.length,
                itemBuilder: (context, index) {
                  final segment = provider.captions[index];
                  final isActive = index == _activeCaptionIndex;
                  return _buildCaptionRow(segment, isDark, isActive: isActive);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCaptionRow(CaptionSegment segment, bool isDark,
      {required bool isActive}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.15))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _ytController.seekTo(
              seconds: segment.startMs / 1000,
              allowSeekAhead: true,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : AppColors.grey100),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _formatTimestamp(segment.startMs),
                style: TextStyle(
                  color: isActive
                      ? AppColors.primary
                      : (isDark ? Colors.white38 : AppColors.textGrey),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: segment.text.split(' ').map((word) {
                return GestureDetector(
                  onTap: () =>
                      _onWordTap(word, contextSentence: segment.text),
                  child: Text(
                    '$word ',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isActive ? FontWeight.w600 : FontWeight.normal,
                      color: isActive
                          ? (isDark ? Colors.white : AppColors.textDark)
                          : (isDark
                              ? Colors.white70
                              : AppColors.textDark.withValues(alpha: 0.75)),
                      decoration: TextDecoration.underline,
                      decorationColor:
                          AppColors.primary.withValues(alpha: 0.25),
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

  // ─────────────────────────────────────────────
  //  Vocab / History Tab
  // ─────────────────────────────────────────────

  Widget _buildVocabTab(bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        final history =
            provider.translationHistoryFor(widget.video.videoId);

        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate_rounded,
                    size: 52,
                    color: isDark ? Colors.white24 : AppColors.grey300),
                const SizedBox(height: 10),
                Text(
                  'Chưa tra từ nào',
                  style: TextStyle(
                    color: isDark ? Colors.white38 : AppColors.textGrey,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Nhấn vào từ trong phụ đề để tra nghĩa',
                  style: TextStyle(
                    color: isDark ? Colors.white24 : AppColors.grey400,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
          itemCount: history.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : AppColors.grey200,
          ),
          itemBuilder: (context, i) =>
              _buildHistoryItem(history[i], isDark),
        );
      },
    );
  }

  Widget _buildHistoryItem(WordTranslation item, bool isDark) {
    return InkWell(
      onTap: () =>
          _onWordTap(item.word, contextSentence: item.contextSentence),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        item.word,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      if (item.phonetic.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          item.phonetic,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? Colors.white38
                                : AppColors.textGrey,
                          ),
                        ),
                      ],
                      if (item.partOfSpeech.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.partOfSpeech,
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (item.hasTranslation) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.translation,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.85)
                            : AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (item.contextSentence != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '"${item.contextSentence}"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: isDark ? Colors.white30 : AppColors.textGrey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark ? Colors.white.withValues(alpha: 0.20) : AppColors.grey300,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Helpers
  // ─────────────────────────────────────────────

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      backgroundColor: AppColors.primary,
    ));
  }

  String _formatTimestamp(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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

// ─────────────────────────────────────────────────────────────────────────────
//  Action Button widget
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDark;
  final Color? color;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? (isDark ? Colors.white60 : AppColors.textGrey);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(10),
            border: color != null
                ? Border.all(
                    color: color!.withValues(alpha: 0.25),
                    width: 1,
                  )
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: effectiveColor),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: effectiveColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Word Translation Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _WordTranslationSheet extends StatefulWidget {
  final String word;
  final String? contextSentence;
  final String videoId;
  final YouTubeProvider provider;

  const _WordTranslationSheet({
    required this.word,
    required this.videoId,
    required this.provider,
    this.contextSentence,
  });

  @override
  State<_WordTranslationSheet> createState() => _WordTranslationSheetState();
}

class _WordTranslationSheetState extends State<_WordTranslationSheet> {
  late Future<WordTranslation> _translationFuture;

  @override
  void initState() {
    super.initState();
    _translationFuture = widget.provider.translateWord(
      widget.word,
      videoId: widget.videoId,
      contextSentence: widget.contextSentence,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: FutureBuilder<WordTranslation>(
        future: _translationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoading(isDark);
          }
          final t = snapshot.data ?? WordTranslation(word: widget.word);
          return _buildResult(context, t, isDark);
        },
      ),
    );
  }

  Widget _buildLoading(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dragHandle(isDark),
          const SizedBox(height: 24),
          Text(
            widget.word,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          const LottieLoadingWidget.medium(),
          const SizedBox(height: 8),
          Text(
            'Đang tra từ…',
            style: TextStyle(
                color: isDark ? Colors.white54 : AppColors.textGrey,
                fontSize: 13),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, WordTranslation t, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(child: _dragHandle(isDark)),
          const SizedBox(height: 20),

          // Word + phonetic
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                t.word,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary),
              ),
              if (t.hasPhonetic) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    t.phonetic,
                    style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white54 : AppColors.textGrey),
                  ),
                ),
              ],
            ],
          ),

          if (t.partOfSpeech.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t.partOfSpeech,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Vietnamese translation
          if (t.hasTranslation) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tiếng Việt',
                    style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : AppColors.textGrey,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    t.translation,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // English definition
          if (t.hasDefinition) ...[
            _sectionLabel('Định nghĩa', isDark),
            const SizedBox(height: 4),
            Text(
              t.definition,
              style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.87)
                      : AppColors.textDark,
                  height: 1.5),
            ),
            const SizedBox(height: 12),
          ],

          // Examples
          if (t.examples.isNotEmpty) ...[
            _sectionLabel('Ví dụ', isDark),
            const SizedBox(height: 6),
            ...t.examples.take(2).map(
              (ex) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(color: AppColors.primary)),
                    Expanded(
                      child: Text(
                        ex,
                        style: TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            color: isDark
                                ? Colors.white70
                                : AppColors.textDark,
                            height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Context sentence
          if (widget.contextSentence != null) ...[
            _sectionLabel('Câu trong video', isDark),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : AppColors.grey100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: _HighlightedSentence(
                sentence: widget.contextSentence!,
                word: t.word,
                isDark: isDark,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Đóng'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: isDark ? Colors.white24 : AppColors.grey300),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    showQuickSaveWordSheet(
                      context,
                      word: t.word,
                      sourceType: 'youtube',
                      sourceReference: widget.videoId,
                      contextSentence: widget.contextSentence,
                      definition: t.hasDefinition ? t.definition : null,
                      translation: t.hasTranslation ? t.translation : null,
                      partOfSpeech:
                          t.partOfSpeech.isNotEmpty ? t.partOfSpeech : null,
                    );
                  },
                  icon: const Icon(Icons.bookmark_add_rounded, size: 16),
                  label: const Text('Lưu từ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dragHandle(bool isDark) => Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: isDark ? Colors.white24 : AppColors.grey300,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  Widget _sectionLabel(String text, bool isDark) => Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white38 : AppColors.textGrey,
          letterSpacing: 0.5,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Highlighted Sentence — bolds the tapped word in its context sentence
// ─────────────────────────────────────────────────────────────────────────────

class _HighlightedSentence extends StatelessWidget {
  final String sentence;
  final String word;
  final bool isDark;

  const _HighlightedSentence({
    required this.sentence,
    required this.word,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final lowerSentence = sentence.toLowerCase();
    final lowerWord = word.toLowerCase();
    final idx = lowerSentence.indexOf(lowerWord);

    if (idx < 0) {
      return Text(
        sentence,
        style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: isDark ? Colors.white70 : AppColors.textDark),
      );
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: isDark ? Colors.white70 : AppColors.textDark),
        children: [
          TextSpan(text: sentence.substring(0, idx)),
          TextSpan(
            text: sentence.substring(idx, idx + word.length),
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: sentence.substring(idx + word.length)),
        ],
      ),
    );
  }
}
