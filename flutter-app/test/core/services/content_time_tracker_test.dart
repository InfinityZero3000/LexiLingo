import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/content_time_tracker.dart';
import 'package:lexilingo_app/features/games/data/repositories/games_repository.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';

/// Reading and watching time, credited in idempotent chunks.
///
/// The two things worth pinning down: an open screen is not reading, and the
/// same chunk must never be paid twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ContentTimeTracker tracker(_RecordingRepository repository) =>
      ContentTimeTracker(
        source: 'book',
        sourceIdPrefix: 'read:book-1',
        sourceDetail: 'reading_time',
        chunk: const Duration(minutes: 5),
        xpPerChunk: 5,
        awarder: repository,
      );

  group('chunking', () {
    test('awards nothing until a whole chunk is spent', () async {
      final repository = _RecordingRepository();
      tracker(repository).add(const Duration(minutes: 4, seconds: 59));
      await Future<void>.delayed(Duration.zero);

      expect(repository.awards, isEmpty);
    });

    test('awards one chunk per completed chunk, in order', () async {
      final repository = _RecordingRepository();
      tracker(repository).add(const Duration(minutes: 11));
      await Future<void>.delayed(Duration.zero);

      expect(repository.awards.map((a) => a.sourceId), [
        'read:book-1:0',
        'read:book-1:1',
      ]);
    });

    test('reports the chunk length, not the time accumulated so far', () async {
      final repository = _RecordingRepository();
      tracker(repository).add(const Duration(minutes: 10));
      await Future<void>.delayed(Duration.zero);

      expect(
        repository.awards.map((a) => a.durationSeconds),
        everyElement(300),
      );
    });

    test('never re-awards a chunk already paid', () async {
      final repository = _RecordingRepository();
      final instance = tracker(repository);

      instance.add(const Duration(minutes: 5));
      instance.add(const Duration(minutes: 1));
      instance.add(const Duration(minutes: 4));
      await Future<void>.delayed(Duration.zero);

      expect(repository.awards.map((a) => a.sourceId), [
        'read:book-1:0',
        'read:book-1:1',
      ]);
    });

    test('ignores a negative or zero delta', () async {
      final repository = _RecordingRepository();
      final instance = tracker(repository);

      instance.add(Duration.zero);
      instance.add(const Duration(minutes: -10));
      await Future<void>.delayed(Duration.zero);

      expect(instance.elapsed, Duration.zero);
      expect(repository.awards, isEmpty);
    });

    test('carries the source and detail the quests filter on', () async {
      final repository = _RecordingRepository();
      tracker(repository).add(const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);

      expect(repository.awards.single.source, 'book');
      expect(repository.awards.single.sourceDetail, 'reading_time');
      expect(repository.awards.single.baseXp, 5);
    });
  });

  group('idle and lifecycle', () {
    test('a tick counts only while something happened recently', () {
      final repository = _RecordingRepository();
      final instance = ContentTimeTracker(
        source: 'book',
        sourceIdPrefix: 'read:book-1',
        sourceDetail: 'reading_time',
        idleAfter: const Duration(minutes: 2),
        awarder: repository,
      );

      // No start(): drive the same decision the ticker makes, without waiting
      // real seconds for it.
      instance.markActive();
      expect(instance.shouldCountTick(), isTrue);
    });

    test('stops counting once idle longer than the window', () {
      final repository = _RecordingRepository();
      final instance = ContentTimeTracker(
        source: 'book',
        sourceIdPrefix: 'read:book-1',
        sourceDetail: 'reading_time',
        idleAfter: const Duration(milliseconds: 1),
        awarder: repository,
      );

      instance.markActive();
      expect(
        instance.shouldCountTick(now: DateTime.now().add(const Duration(minutes: 1))),
        isFalse,
      );
    });

    test('counts nothing before any activity is reported', () {
      final instance = ContentTimeTracker(
        source: 'book',
        sourceIdPrefix: 'read:book-1',
        sourceDetail: 'reading_time',
        awarder: _RecordingRepository(),
      );

      expect(instance.shouldCountTick(), isFalse);
    });

    test('a backgrounded app counts nothing', () {
      final instance = ContentTimeTracker(
        source: 'book',
        sourceIdPrefix: 'read:book-1',
        sourceDetail: 'reading_time',
        awarder: _RecordingRepository(),
      );

      instance.markActive();
      instance.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(instance.shouldCountTick(), isFalse);
    });

    test('coming back to the foreground counts as activity', () {
      final instance = ContentTimeTracker(
        source: 'book',
        sourceIdPrefix: 'read:book-1',
        sourceDetail: 'reading_time',
        awarder: _RecordingRepository(),
      );

      instance.didChangeAppLifecycleState(AppLifecycleState.paused);
      instance.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(instance.shouldCountTick(), isTrue);
    });
  });

  test('a part-finished chunk is dropped, not rounded up', () async {
    final repository = _RecordingRepository();
    final instance = tracker(repository);

    instance.add(const Duration(minutes: 4, seconds: 50));
    instance.stop();
    await Future<void>.delayed(Duration.zero);

    expect(repository.awards, isEmpty);
  });
}

class _Award {
  _Award({
    required this.source,
    required this.baseXp,
    required this.sourceId,
    required this.sourceDetail,
    required this.durationSeconds,
  });

  final String source;
  final int baseXp;
  final String? sourceId;
  final String? sourceDetail;
  final int? durationSeconds;
}

class _RecordingRepository implements GamesRepository {
  final List<_Award> awards = [];

  @override
  Future<XPAwardResult> awardXP({
    required String source,
    required int baseXp,
    String? sourceId,
    String? sourceDetail,
    int? durationSeconds,
    int? score,
    int? totalQuestions,
  }) async {
    awards.add(
      _Award(
        source: source,
        baseXp: baseXp,
        sourceId: sourceId,
        sourceDetail: sourceDetail,
        durationSeconds: durationSeconds,
      ),
    );
    throw _StopHere();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The tracker swallows award failures by design; throwing proves it does.
class _StopHere implements Exception {}
