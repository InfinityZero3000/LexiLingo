import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/podcast_audio_handler.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/lottie_loading_widget.dart';
import '../../../games/data/repositories/games_repository.dart';
import '../../domain/entities/podcast_entities.dart';
import '../widgets/audio_player_controls.dart';
import '../widgets/transcript_panel.dart';

/// Full podcast player screen.
///
/// Delegates all audio playback to the [PodcastAudioHandler] singleton
/// registered in GetIt. This means playback survives screen pops and the
/// user can control audio from the OS lock-screen / notification shade.
///
/// XP is awarded via [GamesRepository.awardXP] when listen progress
/// exceeds 80 % of total duration (fire-once, silently swallowed on error).
///
/// Phase 4: Podcast — skill: audio-format-optimization.
class PodcastPlayerScreen extends StatefulWidget {
  final PodcastEpisode episode;
  final String artworkUrl;

  const PodcastPlayerScreen({
    super.key,
    required this.episode,
    required this.artworkUrl,
  });

  @override
  State<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends State<PodcastPlayerScreen> {
  PodcastAudioHandler? _handler;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  bool _xpAwarded = false;
  bool _transcriptLoading = false;
  String? _transcript;
  bool _transcriptExpanded = false;
  bool _handlerInitializing = false;

  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    _tryInitHandler();
  }

  void _tryInitHandler({int attempt = 0}) {
    if (!mounted) return;
    if (sl.isRegistered<PodcastAudioHandler>()) {
      _handler = sl<PodcastAudioHandler>();
      if (_handlerInitializing) {
        setState(() => _handlerInitializing = false);
      }
      _setupPlayer();
    } else if (attempt < 20) {
      // Handler still initializing in background — retry after 500 ms
      if (!_handlerInitializing) setState(() => _handlerInitializing = true);
      Future.delayed(const Duration(milliseconds: 500), () {
        _tryInitHandler(attempt: attempt + 1);
      });
    }
  }

  Future<void> _setupPlayer() async {
    // Position stream
    _subs.add(
      _handler!.positionStream.listen((pos) {
        if (!mounted) return;
        setState(() => _position = pos);
        _checkXpAward(pos);
      }),
    );

    // Duration stream
    _subs.add(
      _handler!.durationStream.listen((dur) {
        if (!mounted) return;
        if (dur != null) setState(() => _duration = dur);
      }),
    );

    // Player state stream
    _subs.add(
      _handler!.playerStateStream.listen((state) {
        if (!mounted) return;
        setState(() => _isPlaying = state.playing);
      }),
    );

    // Load episode into the handler (resolves local/remote source)
    try {
      await _handler!.setEpisode(widget.episode);
      // Restore previous listen position
      final prevMs = widget.episode.listenProgress * 1000;
      if (prevMs > 0) {
        await _handler!.seek(Duration(milliseconds: prevMs.toInt()));
      }
    } catch (e) {
      debugPrint('PodcastPlayerScreen: failed to load audio: $e');
    }
  }

  void _checkXpAward(Duration position) {
    if (_xpAwarded) return;
    if (_duration == Duration.zero) return;
    final ratio = position.inMilliseconds / _duration.inMilliseconds;
    if (ratio >= 0.8) {
      _xpAwarded = true;
      _awardXp();
    }
  }

  Future<void> _awardXp() async {
    try {
      await sl<GamesRepository>().awardXP(
        source: 'podcast',
        baseXp: 20,
        sourceId: widget.episode.guid,
        durationSeconds: _duration.inSeconds,
      );
    } catch (_) {
      // Silently ignore — XP award must never crash the player.
    }
  }

  void _skipBack() {
    if (_handler != null) _handler!.rewind();
  }

  void _skipForward() {
    if (_handler != null) _handler!.fastForward();
  }

  Future<void> _changeSpeed(double speed) async {
    setState(() => _playbackSpeed = speed);
    await _handler?.setSpeed(speed);
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    // Do NOT dispose the handler — it is a shared singleton and background
    // playback should continue after the screen is popped.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(widget.episode.cefrLevel ?? 'B1');

    // Handler not yet available
    if (_handler == null) {
      return Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : AppColors.backgroundLight,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: const Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: LottieLoadingWidget.medium(),
          ),
        ),
      );
    }

    final progressRatio = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Navigator.pop(context),
          tooltip: 'notifications.tooltipBack'.tr(),
        ),
        title: Text(
          widget.episode.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Artwork ──
            const SizedBox(height: 8),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: widget.artworkUrl.isNotEmpty
                    ? Image.network(
                        widget.artworkUrl,
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.never,
                        errorBuilder: (_, __, ___) =>
                            _buildArtworkFallback(cefrColor),
                      )
                    : _buildArtworkFallback(cefrColor),
              ),
            ),
            const SizedBox(height: 20),

            // ── Episode title ──
            Text(
              widget.episode.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                height: 1.3,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),

            // ── CEFR badge ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: cefrColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.episode.cefrLevel ?? 'B1',
                style: TextStyle(
                  color: AppColors.surfaceLight,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ── Progress bar ──
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressRatio.toDouble(),
                minHeight: 4,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : AppColors.grey200,
                valueColor: AlwaysStoppedAnimation<Color>(cefrColor),
              ),
            ),
            const SizedBox(height: 6),

            // ── Time labels ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(_position),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                  ),
                ),
                Text(
                  _formatDuration(_duration),
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : AppColors.textGrey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Audio player controls ──
            AudioPlayerControls(
              onPlay: _handler!.play,
              onPause: _handler!.pause,
              onSkipBack: _skipBack,
              onSkipForward: _skipForward,
              onSpeedChange: _changeSpeed,
              isPlaying: _isPlaying,
              playbackSpeed: _playbackSpeed,
              position: _position,
              duration: _duration,
              episodeTitle: widget.episode.title,
              artworkUrl: widget.artworkUrl,
            ),
            const SizedBox(height: 24),

            // ── Transcript section ──
            _buildTranscriptSection(isDark),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Transcript section (collapsible)
  // ──────────────────────────────────────

  Widget _buildTranscriptSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Collapse/expand header
        InkWell(
          onTap: () =>
              setState(() => _transcriptExpanded = !_transcriptExpanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'podcast.transcriptLabel'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _transcriptExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: isDark ? Colors.white54 : AppColors.textGrey,
                ),
              ],
            ),
          ),
        ),
        if (_transcriptExpanded) ...[
          const SizedBox(height: 10),
          TranscriptPanel(
            transcript: _transcript,
            isLoading: _transcriptLoading,
            onGenerateTranscript: _generateTranscript,
          ),
        ],
      ],
    );
  }

  Future<void> _generateTranscript() async {
    setState(() => _transcriptLoading = true);
    try {
      // Placeholder: real implementation would call AI service.
      await Future<void>.delayed(const Duration(seconds: 1));
      setState(() => _transcript = null);
    } finally {
      if (mounted) setState(() => _transcriptLoading = false);
    }
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  Widget _buildArtworkFallback(Color color) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(Icons.podcasts_rounded, size: 72, color: color),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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
