import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:lexilingo_app/core/services/content_time_tracker.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/known_words_service.dart';
import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/youtube_entities.dart';
import '../providers/youtube_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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
  final Map<int, GlobalKey> _captionRowKeys = {};
  // Layouts re-arrange around the player; the key lets it be re-parented
  // instead of rebuilt, so a rotate or resize does not reload the video.
  final GlobalKey _playerKey = GlobalKey();

  int _currentPositionMs = 0;
  Timer? _positionTimer;
  int _activeCaptionIndex = -1;
  double _playbackSpeed = 1.0;
  bool _streakUpdated = false;
  bool _polling = false;

  /// Watch time, credited in idempotent chunks by the shared tracker.
  ///
  /// Fed position *advances* rather than wall-clock ticks: a tick can only ever
  /// contribute as much as a tick covers, so dragging the scrubber forward
  /// credits nothing because the jump is clamped to [_kWatchTickCapMs].
  late final ContentTimeTracker _watchTime;

  static const _kWatchTickCapMs = 1000;

  static const _kSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();

    _tabController = TabController(length: 2, vsync: this);

    _ytController = YoutubePlayerController(
      key: widget.video.videoId,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        enableCaption: false,
        strictRelatedVideos: true,
        playsInline: true,
      ),
    );
    // fromVideoId(autoPlay:) fires this unawaited, so a player that is not
    // ready within the package's 30s timeout became an uncaught error.
    _ytController.loadVideoById(videoId: widget.video.videoId).ignore();

    // No start(): the tracker's own ticker would count wall clock, and watching
    // is measured from playback advancing instead.
    _watchTime = ContentTimeTracker(
      source: 'youtube',
      sourceIdPrefix: widget.video.videoId,
      sourceDetail: 'video_watch',
    );

    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _syncPosition();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<YouTubeProvider>();
      provider.loadCaptions(widget.video.videoId);
      provider.addToHistory(widget.video);
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _tabController.dispose();
    _ytController.close();
    _positionTimer?.cancel();
    _watchTime.stop();
    _captionScrollController.dispose();
    super.dispose();
  }

  /// Credit each completed chunk of watching. Fire-and-forget: a learner has
  /// already watched the video by the time this runs, and a failed award must
  /// never interrupt playback.
  Future<void> _syncPosition() async {
    if (_polling) return;
    _polling = true;
    try {
      final seconds = await _ytController.currentTime;
      final posMs = (seconds * 1000).round();
      if (!mounted || posMs == _currentPositionMs) return;

      _watchTime.add(
        Duration(
          milliseconds: (posMs - _currentPositionMs).clamp(0, _kWatchTickCapMs),
        ),
      );

      // Update streak once per session after 30 seconds of watching
      if (!_streakUpdated && posMs >= 30000) {
        _streakUpdated = true;
        context.read<StreakProvider>().updateStreak();
      }

      final provider = context.read<YouTubeProvider>();
      int newIndex = -1;
      for (int i = 0; i < provider.captions.length; i++) {
        if (provider.captions[i].isActiveAt(posMs)) {
          newIndex = i;
          break;
        }
      }

      final changed = newIndex != _activeCaptionIndex;
      setState(() {
        _currentPositionMs = posMs;
        _activeCaptionIndex = newIndex;
      });

      if (changed && newIndex >= 0) _scrollToCaption(newIndex);
    } catch (_) {
    } finally {
      _polling = false;
    }
  }

  /// Keeps the active line a third of the way down, like synced lyrics.
  /// Rows vary in height, so position comes from the built row, not an index.
  void _scrollToCaption(int index, {bool retry = true}) {
    final ctx = _captionRowKeys[index]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeInOutCubic,
      );
      return;
    }
    // Row not built (seeked far away): jump near it, then settle once built.
    if (!retry || !_captionScrollController.hasClients) return;
    final pos = _captionScrollController.position;
    _captionScrollController.jumpTo(
      (index * 72.0).clamp(pos.minScrollExtent, pos.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCaption(index, retry: false);
    });
  }

  void _onWordTap(String word, {String? contextSentence}) {
    final cleanWord = word
        .replaceAll(RegExp(r"[^\w\s'-]"), '')
        .trim()
        .toLowerCase();
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
        padding: const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, 28),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.textInverted,
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
                  color: isDark
                      ? AppColors.textInverted.withValues(alpha: 0.24)
                      : AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'voice.playbackSpeed'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : (isDark
                                ? AppColors.textInverted.withValues(alpha: 0.08)
                                : AppColors.grey100),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : (isDark
                                  ? AppColors.textInverted.withValues(
                                      alpha: 0.1,
                                    )
                                  : AppColors.grey200),
                      ),
                    ),
                    child: Text(
                      speed == 1.0 ? 'voice.speedNormal'.tr() : '${speed}x',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? AppColors.textInverted
                            : (isDark
                                  ? AppColors.textOnDarkSecondary
                                  : Theme.of(context).colorScheme.onSurface),
                        fontWeight: FontWeight.w600,
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
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF7F8FC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeController,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tabView = TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [_buildCaptionsTab(isDark), _buildVocabTab(isDark)],
              );
              final tabs = Expanded(child: tabView);

              // A full-width 16:9 player is taller than a landscape window,
              // so wide screens put the transcript beside the video.
              if (constraints.maxWidth >= 720 &&
                  constraints.maxWidth > constraints.maxHeight) {
                return Column(
                  children: [
                    _buildTopHeader(isDark),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildPlayerArea(isDark),
                                  _buildActiveSubtitleCard(isDark),
                                  _buildInfoBar(isDark),
                                  _buildActionBar(isDark),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: [
                                const SizedBox(height: AppSpacing.sm),
                                _buildTabBar(isDark),
                                tabs,
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }

              // The stacked header, player and action rows need ~460px before
              // the tabs get any room; a short window (landscape phone, large
              // text) would overflow, so it scrolls as a whole instead.
              final short = constraints.maxHeight < 600;
              final stacked = Column(
                children: [
                  _buildTopHeader(isDark),
                  if (short)
                    _buildPlayerArea(isDark)
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * 0.4,
                      ),
                      child: Center(
                        heightFactor: 1,
                        child: _buildPlayerArea(isDark),
                      ),
                    ),
                  _buildActiveSubtitleCard(isDark),
                  _buildInfoBar(isDark),
                  _buildActionBar(isDark),
                  _buildTabBar(isDark),
                  if (short) SizedBox(height: 360, child: tabView) else tabs,
                ],
              );
              return short ? SingleChildScrollView(child: stacked) : stacked;
            },
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Top Header Bar
  // ─────────────────────────────────────────────

  Widget _buildTopHeader(bool isDark) {
    return Container(
      color: isDark ? AppColors.backgroundDark : AppColors.textInverted,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 10,
      ),
      child: Row(
        children: [
          AppBackButton(
            onPressed: () => Navigator.pop(context),
            color: isDark
                ? AppColors.textInverted
                : Theme.of(context).colorScheme.onSurface,
            iconSize: 18,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'youtube.learnThroughVideo'.tr(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Player
  // ─────────────────────────────────────────────

  Widget _buildPlayerArea(bool isDark) {
    return AspectRatio(
      key: _playerKey,
      aspectRatio: 16 / 9,
      child: Container(
        // Letterbox behind the video must be pure black in both themes.
        color: Colors.black,
        child: YoutubePlayer(controller: _ytController),
      ),
    );
  }

  Widget _buildActiveSubtitleCard(bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingCaptions) {
          return const SizedBox.shrink();
        }
        final captions = provider.captions;
        final hasActive =
            _activeCaptionIndex >= 0 && _activeCaptionIndex < captions.length;
        final activeText = hasActive ? captions[_activeCaptionIndex].text : '';

        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.textInverted.withValues(alpha: 0.05)
                : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: isDark
                  ? AppColors.textInverted.withValues(alpha: 0.1)
                  : Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.subtitles_rounded,
                color: hasActive
                    ? Theme.of(context).colorScheme.primary
                    : (isDark
                          ? AppColors.textInverted.withValues(alpha: 0.3)
                          : AppColors.grey400),
                size: 20,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: hasActive
                    ? Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: activeText.split(' ').map((word) {
                          return GestureDetector(
                            onTap: () =>
                                _onWordTap(word, contextSentence: activeText),
                            child: Text(
                              '$word ',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? AppColors.textInverted
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                    decoration: TextDecoration.underline,
                                    decorationColor: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.4),
                                    decorationStyle: TextDecorationStyle.dashed,
                                  ),
                            ),
                          );
                        }).toList(),
                      )
                    : Text(
                        (switch (provider.captionsStatus) {
                          CaptionsStatus.none => 'youtube.noSubtitles',
                          CaptionsStatus.unavailable =>
                            'youtube.subtitlesUnavailable',
                          _ => 'youtube.subtitlePlaceholder',
                        }).tr(),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: isDark
                              ? AppColors.textInverted.withValues(alpha: 0.3)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              if (provider.captionsStatus == CaptionsStatus.unavailable)
                IconButton(
                  tooltip: 'common.retry'.tr(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => provider.loadCaptions(widget.video.videoId),
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────
  //  Info Bar (title + channel)
  // ─────────────────────────────────────────────

  Widget _buildInfoBar(bool isDark) {
    return Container(
      color: isDark ? AppColors.backgroundDark : AppColors.textInverted,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        10,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Channel avatar
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.person_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.video.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppColors.textInverted
                        : Theme.of(context).colorScheme.onSurface,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.video.channelTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? AppColors.textOnDarkMuted
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.video.cefrLevel.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: _cefrColor(widget.video.cefrLevel),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          widget.video.cefrLevel,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: AppColors.textInverted,
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
          color: isDark ? AppColors.backgroundDark : AppColors.textInverted,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            10,
          ),
          child: Row(
            children: [
              _ActionButton(
                icon: isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: isSaved
                    ? 'youtube.saved'.tr()
                    : 'youtube.saveVideo'.tr(),
                color: isSaved ? Theme.of(context).colorScheme.primary : null,
                isDark: isDark,
                onTap: () {
                  if (isSaved) {
                    provider.unsaveVideo(widget.video.videoId);
                    _showSnack('youtube.removedFromSaved'.tr());
                  } else {
                    provider.saveVideo(widget.video);
                    _showSnack('youtube.videoSaved'.tr());
                  }
                },
              ),
              _ActionButton(
                icon: Icons.speed_rounded,
                label: _playbackSpeed == 1.0
                    ? 'youtube.speed'.tr()
                    : '${_playbackSpeed}x',
                isDark: isDark,
                color: _playbackSpeed != 1.0
                    ? Theme.of(context).colorScheme.primary
                    : null,
                onTap: _showSpeedSheet,
              ),
              _ActionButton(
                icon: Icons.open_in_new_rounded,
                label: 'YouTube',
                isDark: isDark,
                onTap: () async {
                  final url = Uri.parse(
                    'https://www.youtube.com/watch?v=${widget.video.videoId}',
                  );
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              Consumer<YouTubeProvider>(
                builder: (context, prov, _) {
                  final histCount = prov
                      .translationHistoryFor(widget.video.videoId)
                      .length;
                  return _ActionButton(
                    icon: Icons.history_edu_rounded,
                    label: histCount > 0
                        ? 'youtube.wordCount'.tr(
                            namedArgs: {'count': '$histCount'},
                          )
                        : 'lesson.vocabulary'.tr(),
                    isDark: isDark,
                    color: histCount > 0
                        ? Theme.of(context).colorScheme.primary
                        : null,
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
      color: isDark ? AppColors.backgroundDark : AppColors.textInverted,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 0),
      child: Column(
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.textInverted.withValues(alpha: 0.07)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(3),
              labelColor: AppColors.textInverted,
              unselectedLabelColor: isDark
                  ? AppColors.textOnDarkMuted
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              labelStyle: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              unselectedLabelStyle: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(text: 'youtube.subtitles'.tr()),
                Tab(text: 'youtube.lookedUpWords'.tr()),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  Captions Tab
  // ─────────────────────────────────────────────

  /// "No subtitles" is final; "could not load" is not, so it gets a retry.
  Widget _buildNoCaptionsState(YouTubeProvider provider, bool isDark) {
    final unavailable = provider.captionsStatus == CaptionsStatus.unavailable;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              unavailable
                  ? Icons.cloud_off_rounded
                  : Icons.subtitles_off_rounded,
              size: 52,
              color: isDark
                  ? AppColors.textInverted.withValues(alpha: 0.24)
                  : AppColors.grey300,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              (unavailable
                      ? 'youtube.subtitlesUnavailable'
                      : 'youtube.noSubtitles')
                  .tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: isDark
                    ? AppColors.textOnDarkSecondary
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (unavailable
                      ? 'youtube.subtitlesUnavailableHint'
                      : 'youtube.noSubtitlesHint')
                  .tr(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: isDark
                    ? AppColors.textOnDarkMuted
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (unavailable) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: () => provider.loadCaptions(widget.video.videoId),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text('common.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCaptionsTab(bool isDark) {
    return Consumer<YouTubeProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingCaptions) {
          return const Center(child: LottieLoadingWidget.medium());
        }

        if (provider.captions.isEmpty) {
          return _buildNoCaptionsState(provider, isDark);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                6,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.subtitles_rounded,
                    size: 15,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'youtube.segmentCount'.tr(
                        namedArgs: {'count': '${provider.captions.length}'},
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textOnDarkMuted
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      'youtube.tapWordToLookUp'.tr(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isDark
                            ? AppColors.textInverted.withValues(alpha: 0.3)
                            : AppColors.grey400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _captionScrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.xl,
                ),
                itemCount: provider.captions.length,
                itemBuilder: (context, index) {
                  final segment = provider.captions[index];
                  final isActive = index == _activeCaptionIndex;
                  return _buildCaptionRow(
                    index,
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

  Widget _buildCaptionRow(
    int index,
    CaptionSegment segment,
    bool isDark, {
    required bool isActive,
  }) {
    return AnimatedContainer(
      key: _captionRowKeys.putIfAbsent(index, GlobalKey.new),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isActive
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: isActive
            ? Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.15),
              )
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
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.15)
                    : (isDark
                          ? AppColors.textInverted.withValues(alpha: 0.06)
                          : AppColors.grey100),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                _formatTimestamp(segment.startMs),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : (isDark
                            ? AppColors.textOnDarkMuted
                            : Theme.of(context).colorScheme.onSurfaceVariant),
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: AnimatedOpacity(
              opacity: isActive ? 1 : 0.55,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              child: Wrap(
                spacing: 3,
                runSpacing: 3,
                children: segment.text.split(' ').map((word) {
                  return GestureDetector(
                    onTap: () =>
                        _onWordTap(word, contextSentence: segment.text),
                    child: Text(
                      '$word ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textInverted
                            : Theme.of(context).colorScheme.onSurface,
                        decoration: TextDecoration.underline,
                        decorationColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.25),
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  );
                }).toList(),
              ),
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
        final history = provider.translationHistoryFor(widget.video.videoId);

        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.translate_rounded,
                  size: 52,
                  color: isDark
                      ? AppColors.textInverted.withValues(alpha: 0.24)
                      : AppColors.grey300,
                ),
                const SizedBox(height: 10),
                Text(
                  'youtube.noLookupsYet'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? AppColors.textOnDarkMuted
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'youtube.tapWordInSubtitle'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textInverted.withValues(alpha: 0.24)
                        : AppColors.grey400,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          itemCount: history.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            indent: 14,
            endIndent: 14,
            color: isDark
                ? AppColors.textInverted.withValues(alpha: 0.05)
                : AppColors.grey200,
          ),
          itemBuilder: (context, i) => _buildHistoryItem(history[i], isDark),
        );
      },
    );
  }

  Widget _buildHistoryItem(WordTranslation item, bool isDark) {
    return InkWell(
      onTap: () => _onWordTap(item.word, contextSentence: item.contextSentence),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.textInverted
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      if (item.phonetic.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          item.phonetic,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: isDark
                                    ? AppColors.textOnDarkMuted
                                    : Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      if (item.partOfSpeech.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.partOfSpeech,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.85)
                            : Theme.of(context).colorScheme.primary,
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: isDark
                            ? AppColors.textInverted.withValues(alpha: 0.3)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isDark
                  ? AppColors.textInverted.withValues(alpha: 0.20)
                  : AppColors.grey300,
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
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
        return context.status.success;
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
        return Theme.of(context).colorScheme.primary;
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
        color ??
        (isDark
            ? AppColors.textOnDarkMuted
            : Theme.of(context).colorScheme.onSurfaceVariant);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.textInverted.withValues(alpha: 0.07)
                : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: color != null
                ? Border.all(color: color!.withValues(alpha: 0.25), width: 1)
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: effectiveColor),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
  bool _isSavingWord = false;
  bool _isSavedWord = false;
  UiText? _saveError;

  @override
  void initState() {
    super.initState();
    _translationFuture = widget.provider.translateWord(
      widget.word,
      videoId: widget.videoId,
      contextSentence: widget.contextSentence,
    );
    _checkAlreadySaved();
  }

  /// Words saved in a previous session must still read as "already saved"
  /// here — otherwise this sheet always starts from a blank slate even
  /// though the backend already has the word in the user's collection.
  Future<void> _checkAlreadySaved() async {
    final known = await sl<KnownWordsService>().getKnownWords();
    if (!mounted) return;
    if (known.contains(widget.word.trim().toLowerCase())) {
      setState(() => _isSavedWord = true);
    }
  }

  Future<void> _quickSave(WordTranslation t) async {
    if (_isSavingWord || _isSavedWord) return;

    setState(() {
      _isSavingWord = true;
      _saveError = null;
    });

    try {
      final service = sl<QuickSaveVocabularyService>();
      final result = await service.quickSaveWord(
        word: t.word,
        sourceType: 'youtube',
        sourceReference: widget.videoId,
        contextSentence: widget.contextSentence,
        definition: t.hasDefinition ? t.definition : null,
        translation: t.hasTranslation ? t.translation : null,
        partOfSpeech: t.partOfSpeech.isNotEmpty ? t.partOfSpeech : null,
      );

      if (!mounted) return;

      setState(() {
        _isSavingWord = false;
        _isSavedWord = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyInCollection && result.reviewScheduled
                ? 'vocabulary.resavedForReview'.tr()
                : result.alreadyInCollection
                ? 'youtube.wordAlreadySaved'.tr(
                    namedArgs: {'word': result.normalizedWord},
                  )
                : 'youtube.wordSaved'.tr(
                    namedArgs: {'word': result.normalizedWord},
                  ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.status.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSavingWord = false;
        _saveError = UiText.key('vocabulary.saveWordFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.textInverted,
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
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dragHandle(isDark),
          const SizedBox(height: AppSpacing.xl),
          Text(
            widget.word,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const LottieLoadingWidget.medium(),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'youtube.lookingUp'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isDark
                  ? AppColors.textOnDarkMuted
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _buildResult(BuildContext context, WordTranslation t, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              if (t.hasPhonetic) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    t.phonetic,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? AppColors.textOnDarkMuted
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),

          if (t.partOfSpeech.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                t.partOfSpeech,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Vietnamese translation
          if (t.hasTranslation) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'vocabulary.translationLabel'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: isDark
                          ? AppColors.textOnDarkMuted
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    t.translation,
                    style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textInverted
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // English definition
          if (t.hasDefinition) ...[
            _sectionLabel('vocabulary.definition'.tr(), isDark),
            const SizedBox(height: AppSpacing.xs),
            Text(
              t.definition,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.textInverted.withValues(alpha: 0.87)
                    : Theme.of(context).colorScheme.onSurface,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Examples
          if (t.examples.isNotEmpty) ...[
            _sectionLabel('vocabulary.examples'.tr(), isDark),
            const SizedBox(height: 6),
            ...t.examples
                .take(2)
                .map(
                  (ex) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            ex,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: isDark
                                      ? AppColors.textOnDarkSecondary
                                      : Theme.of(context).colorScheme.onSurface,
                                  height: 1.45,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Context sentence
          if (widget.contextSentence != null) ...[
            _sectionLabel('youtube.sentenceInVideo'.tr(), isDark),
            const SizedBox(height: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.textInverted.withValues(alpha: 0.05)
                    : AppColors.grey100,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: _HighlightedSentence(
                sentence: widget.contextSentence!,
                word: t.word,
                isDark: isDark,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],

          if (_saveError != null) ...[
            const SizedBox(height: 10),
            Text(
              _saveError!.resolve(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: isDark
                          ? AppColors.textInverted.withValues(alpha: 0.24)
                          : AppColors.grey300,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                  ),
                  child: Text('common.close'.tr()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_isSavingWord || _isSavedWord)
                      ? null
                      : () => _quickSave(t),
                  icon: _isSavingWord
                      ? const SizedBox(
                          width: AppSpacing.lg,
                          height: AppSpacing.lg,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textInverted,
                          ),
                        )
                      : Icon(
                          _isSavedWord
                              ? Icons.check_circle_rounded
                              : Icons.bookmark_add_rounded,
                          size: 16,
                        ),
                  label: Text(
                    _isSavingWord
                        ? 'youtube.saving'.tr()
                        : _isSavedWord
                        ? 'youtube.saved'.tr()
                        : 'youtube.saveWord'.tr(),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _isSavedWord
                        ? context.status.success
                        : Theme.of(context).colorScheme.primary,
                    disabledBackgroundColor: _isSavedWord
                        ? context.status.success.withValues(alpha: 0.6)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
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
      color: isDark
          ? AppColors.textInverted.withValues(alpha: 0.24)
          : AppColors.grey300,
      borderRadius: BorderRadius.circular(2),
    ),
  );

  Widget _sectionLabel(String text, bool isDark) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: isDark
          ? AppColors.textOnDarkMuted
          : Theme.of(context).colorScheme.onSurfaceVariant,
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
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          height: 1.45,
          color: isDark
              ? AppColors.textOnDarkSecondary
              : Theme.of(context).colorScheme.onSurface,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          height: 1.45,
          color: isDark
              ? AppColors.textOnDarkSecondary
              : Theme.of(context).colorScheme.onSurface,
        ),
        children: [
          TextSpan(text: sentence.substring(0, idx)),
          TextSpan(
            text: sentence.substring(idx, idx + word.length),
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: sentence.substring(idx + word.length)),
        ],
      ),
    );
  }
}
