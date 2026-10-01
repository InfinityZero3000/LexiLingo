import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/games/data/repositories/games_repository.dart';

/// Reports time spent on a piece of content, in whole chunks.
///
/// Shared by the reader, the article screen and the video player because all
/// three need the same two things and neither is obvious:
///
/// **Chunking, because the award is idempotent.** `/xp/award` dedups on
/// `source_id`, so one award per article could never carry a growing total — the
/// second call for the same id is refused. Each chunk gets its own id, which
/// both survives the screen being closed part-way and stops a long session
/// being counted twice if it is reopened.
///
/// **Idle detection, because an open screen is not reading.** A tick only counts
/// when the app is in the foreground and something happened recently; the caller
/// reports activity through [markActive] on a scroll or a page turn.
class ContentTimeTracker with WidgetsBindingObserver {
  ContentTimeTracker({
    required this.source,
    required this.sourceIdPrefix,
    required this.sourceDetail,
    this.chunk = const Duration(minutes: 5),
    this.xpPerChunk = 5,
    this.idleAfter = const Duration(minutes: 2),
    GamesRepository? awarder,
  }) : _awarder = awarder;

  /// `news` | `book` | `youtube` — must exist in the backend's XP_SOURCE_CAPS.
  final String source;

  /// Unique per piece of content. The award id is `<prefix>:<chunkIndex>`.
  final String sourceIdPrefix;

  /// Distinguishes this from the same source's other awards, so a quest can ask
  /// for quizzes without reading time ticking it.
  final String sourceDetail;

  final Duration chunk;
  final int xpPerChunk;

  /// How long after the last [markActive] a tick still counts.
  ///
  /// The calibration knob: this is reading speed, not a technical limit. A slow
  /// A2 learner can spend well over a minute on one screenful without
  /// scrolling, so a short window would quietly undercount exactly the learners
  /// who read slowest. Too long and a phone left face-up earns XP.
  final Duration idleAfter;

  final GamesRepository? _awarder;

  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  int _awardedChunks = 0;
  DateTime? _lastActiveAt;
  bool _foreground = true;

  static const _tick = Duration(seconds: 1);

  Duration get elapsed => _elapsed;

  GamesRepository? get _repository {
    if (_awarder != null) return _awarder;
    if (!sl.isRegistered<GamesRepository>()) return null;
    return sl<GamesRepository>();
  }

  /// Begin counting. Safe to call once from `initState`.
  void start() {
    if (_ticker != null) return;
    WidgetsBinding.instance.addObserver(this);
    markActive();
    _ticker = Timer.periodic(_tick, (_) => _onTick());
  }

  /// Stop counting and release the lifecycle observer. Call from `dispose`.
  ///
  /// A part-finished chunk is deliberately dropped rather than rounded up: the
  /// learner would otherwise be paid for a chunk they did not spend, and the
  /// next visit starts its own count.
  void stop() {
    if (_ticker == null) return;
    _ticker!.cancel();
    _ticker = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Something happened — a scroll, a page turn, a tap. Keeps ticks counting.
  void markActive() => _lastActiveAt = DateTime.now();

  /// Add time measured by the caller rather than by the ticker.
  ///
  /// The video player uses this: it counts how far playback advanced, so that
  /// dragging the scrubber forward credits nothing.
  void add(Duration delta) {
    if (delta <= Duration.zero) return;
    _elapsed += delta;
    _reportCompletedChunks();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    // Returning to the app is activity; otherwise the first ticks back would be
    // dropped as idle even though the learner just opened it.
    if (_foreground) markActive();
  }

  /// Whether a tick at [now] counts as time spent.
  ///
  /// Named and exposed because this, not the timer, is the behaviour worth
  /// testing: a test can ask the question directly instead of waiting real
  /// seconds for ticks to land.
  @visibleForTesting
  bool shouldCountTick({DateTime? now}) {
    if (!_foreground) return false;
    final lastActive = _lastActiveAt;
    if (lastActive == null) return false;
    return (now ?? DateTime.now()).difference(lastActive) <= idleAfter;
  }

  void _onTick() {
    if (!shouldCountTick()) return;
    _elapsed += _tick;
    _reportCompletedChunks();
  }

  void _reportCompletedChunks() {
    final completed = _elapsed.inMilliseconds ~/ chunk.inMilliseconds;
    for (var index = _awardedChunks; index < completed; index++) {
      unawaited(_award(index));
    }
    _awardedChunks = completed;
  }

  /// Fire-and-forget: the learner has already spent the time by now, and a
  /// failed award must never interrupt reading or playback.
  Future<void> _award(int chunkIndex) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.awardXP(
        source: source,
        baseXp: xpPerChunk,
        sourceId: '$sourceIdPrefix:$chunkIndex',
        sourceDetail: sourceDetail,
        durationSeconds: chunk.inSeconds,
      );
    } catch (e) {
      // An already-credited chunk answers 409 — the dedup doing its job.
      debugPrint('ContentTimeTracker($source): chunk $chunkIndex not awarded: $e');
    }
  }
}
