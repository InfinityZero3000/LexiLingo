import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/services/podcast_audio_handler.dart';
import '../../../../core/widgets/content_kit.dart';
import '../../../../core/widgets/lottie_loading_widget.dart';
import '../../../games/data/repositories/games_repository.dart';
import '../../data/repositories/podcast_repository.dart';
import '../../data/services/listening_history_recorder.dart';
import '../../domain/entities/podcast_entities.dart';
import '../widgets/audio_player_controls.dart';
import '../widgets/player_header.dart';
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

  /// Labels the "continue listening" card; empty when the caller has none.
  final String podcastTitle;

  const PodcastPlayerScreen({
    super.key,
    required this.episode,
    required this.artworkUrl,
    this.podcastTitle = '',
  });

  @override
  State<PodcastPlayerScreen> createState() => _PodcastPlayerScreenState();
}

class _PodcastPlayerScreenState extends State<PodcastPlayerScreen> {
  PodcastAudioHandler? _handler;
  final PodcastRepository _podcastRepository = PodcastRepository();

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _playbackSpeed = 1.0;
  bool _xpAwarded = false;
  bool _transcriptLoading = false;
  String? _transcript;
  bool _transcriptExpanded = false;
  bool _handlerInitializing = false;
  bool _loadError = false;

  // Mirrors PodcastAudioHandler.sleepTimerSecondsRemaining for display only —
  // the timer itself lives on the handler, not here, so it keeps running
  // after this screen is popped.
  int? _sleepTimerSecondsRemaining;

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
        // just_audio ticks ~5x/s; rebuilding the whole screen that often is
        // what made reopening a background podcast stutter.
        if (!mounted || pos.inSeconds == _position.inSeconds) return;
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

    // Sleep timer — read the current value synchronously first (a timer may
    // already be running from before this screen was (re)opened), then
    // follow further ticks.
    _sleepTimerSecondsRemaining = _handler!.sleepTimerSecondsRemaining;
    _subs.add(
      _handler!.sleepTimerSecondsStream.listen((seconds) {
        if (!mounted) return;
        setState(() => _sleepTimerSecondsRemaining = seconds);
      }),
    );

    _recordHistory();
    await _loadEpisode();
  }

  /// Hands the episode to the app-wide recorder, which keeps writing the
  /// learner's place after this screen is popped.
  void _recordHistory() {
    if (!sl.isRegistered<ListeningHistoryRecorder>()) return;
    final handler = _handler!;
    sl<ListeningHistoryRecorder>()
      ..bind(
        owner: handler,
        position: handler.positionStream,
        duration: handler.durationStream,
        playing: handler.playerStateStream.map((s) => s.playing).distinct(),
      )
      ..track(
        episode: widget.episode,
        podcastTitle: widget.podcastTitle,
        artworkUrl: widget.artworkUrl,
      );
  }

  // Load episode into the handler (resolves local/remote source)
  Future<void> _loadEpisode() async {
    if (_loadError) setState(() => _loadError = false);
    try {
      final loaded = await _handler!.setEpisode(widget.episode);
      if (!mounted) return;
      if (!loaded) {
        // Already playing in the background: adopt its live state instead of
        // restarting it from the saved position.
        setState(() {
          _position = _handler!.currentPosition;
          _isPlaying = _handler!.playing;
        });
        return;
      }
      // Pick up where the learner left off.
      final history = await _podcastRepository.getListeningHistory(
        widget.episode.guid,
      );
      // A finished episode has history with no resume point: start it over.
      // listenProgress is only the fallback for episodes with no history yet
      // (it is itself copied from the history's last position).
      final resume = history != null
          ? history.resumeFromSeconds
          : (widget.episode.listenProgress > 5
                ? widget.episode.listenProgress
                : null);
      if (resume != null) await _handler!.seek(Duration(seconds: resume));
    } catch (e) {
      debugPrint('PodcastPlayerScreen: failed to load audio: $e');
      if (mounted) setState(() => _loadError = true);
    }
  }

  void _checkXpAward(Duration position) {
    if (_xpAwarded) return;
    if (_duration == Duration.zero) return;
    final ratio = position.inMilliseconds / _duration.inMilliseconds;
    if (ratio >= 0.8) {
      _xpAwarded = true;
      _awardXp(position);
    }
  }

  Future<void> _awardXp(Duration listened) async {
    try {
      await sl<GamesRepository>().awardXP(
        source: 'podcast',
        baseXp: 20,
        sourceId: widget.episode.guid,
        // How far they actually got, not the episode's full length — the
        // backend turns this into study-time minutes, and the award fires at
        // 80% played, so the full length would overstate every listen.
        durationSeconds: listened.inSeconds,
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
    // Do NOT dispose the handler, and do NOT cancel its sleep timer — it is
    // a shared singleton and both background playback and any running sleep
    // timer must keep going after this screen is popped.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle.light,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
          onPressed: () => Navigator.pop(context),
          tooltip: 'notifications.tooltipBack'.tr(),
        ),
        title: Text(
          'podcast.nowPlaying'.tr().toUpperCase(),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.6,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            PlayerHeader(
              title: widget.episode.title,
              podcastTitle: widget.podcastTitle,
              artworkUrl: widget.artworkUrl,
              level: widget.episode.cefrLevel ?? 'B1',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                children: [
                  if (_handler == null)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: LottieLoadingWidget.medium(),
                    )
                  else
                    AudioPlayerControls(
                      onPlay: _handler!.play,
                      onPause: _handler!.pause,
                      onSkipBack: _skipBack,
                      onSkipForward: _skipForward,
                      onSpeedChange: _changeSpeed,
                      onSeek: _handler!.seek,
                      onSleepTimerSet: (duration) =>
                          _handler!.setSleepTimer(duration),
                      isPlaying: _isPlaying,
                      playbackSpeed: _playbackSpeed,
                      position: _position,
                      duration: _duration,
                      episodeTitle: widget.episode.title,
                      artworkUrl: widget.artworkUrl,
                      sleepTimerSecondsRemaining: _sleepTimerSecondsRemaining,
                    ),
                  if (_loadError) ...[
                    const SizedBox(height: 12),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'podcast.audioLoadFailed'.tr(),
                                style: TextStyle(
                                  color: scheme.onErrorContainer,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _loadEpisode,
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.onErrorContainer,
                                minimumSize: const Size(44, 44),
                              ),
                              child: Text(
                                'common.retry'.tr(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _buildTranscriptSection(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Transcript section (collapsible)
  // ──────────────────────────────────────

  Widget _buildTranscriptSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: InkWell(
            onTap: () =>
                setState(() => _transcriptExpanded = !_transcriptExpanded),
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    PhosphorIconsBold.subtitles,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'podcast.transcriptLabel'.tr(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    _transcriptExpanded
                        ? PhosphorIconsBold.caretUp
                        : PhosphorIconsBold.caretDown,
                    size: 18,
                    color: contentMuted(context),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_transcriptExpanded) ...[
          const SizedBox(height: 12),
          TranscriptPanel(
            transcript: _transcript,
            isLoading: _transcriptLoading,
            onGenerateTranscript: _generateTranscript,
            showHeading: false,
          ),
        ],
      ],
    );
  }

  Future<void> _generateTranscript() async {
    setState(() => _transcriptLoading = true);
    try {
      final transcript = await _podcastRepository.generateTranscript(
        widget.episode,
      );
      if (!mounted) return;
      setState(() => _transcript = transcript);
    } catch (e) {
      debugPrint('PodcastPlayerScreen: failed to generate transcript: $e');
      if (mounted) setState(() => _transcript = null);
    } finally {
      if (mounted) setState(() => _transcriptLoading = false);
    }
  }
}
