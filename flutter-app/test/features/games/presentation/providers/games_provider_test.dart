import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/games/data/repositories/games_repository.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';

class _FakeGamesRepository extends GamesRepository {
  int completionCalls = 0;
  final List<Object> outcomes;
  Completer<XPAwardResult>? pendingCompletion;

  _FakeGamesRepository({List<Object> outcomes = const []})
    : outcomes = List<Object>.of(outcomes);

  @override
  Future<XPAwardResult> completeGameSession({
    required String sessionId,
    required List<Map<String, String>> answers,
    int? clientDurationSeconds,
    int hintsUsed = 0,
  }) async {
    completionCalls++;
    if (pendingCompletion != null) return pendingCompletion!.future;
    final outcome = outcomes.removeAt(0);
    if (outcome is Exception) throw outcome;
    return outcome as XPAwardResult;
  }
}

const _award = XPAwardResult(
  xpAwarded: 10,
  baseXp: 10,
  newTotalXp: 110,
  oldLevel: 1,
  newLevel: 1,
  currentXpInLevel: 10,
);

const _answers = [
  {'id': 'q1', 'answer': 'cat'},
];

void main() {
  test('successful completion applies server award', () async {
    final repository = _FakeGamesRepository(outcomes: [_award]);
    final provider = GamesProvider(repository: repository);

    final result = await provider.completeGame(
      gameType: GameType.wordScramble,
      score: 1,
      totalQuestions: 1,
      correctAnswers: 1,
      answers: _answers,
      sessionId: 'session-1',
    );

    expect(result?.xpAwarded, 10);
    expect(provider.lastGameResult?.xpEarned, 10);
    expect(provider.awardStatus, GameAwardStatus.awarded);
    expect(repository.completionCalls, 1);
  });

  test('failed completion preserves payload and can retry', () async {
    final repository = _FakeGamesRepository(
      outcomes: [Exception('offline'), _award],
    );
    final provider = GamesProvider(repository: repository);

    final first = await provider.completeGame(
      gameType: GameType.wordScramble,
      score: 1,
      totalQuestions: 1,
      correctAnswers: 1,
      answers: _answers,
      sessionId: 'session-1',
    );
    final retried = await provider.retryLastCompletion();

    expect(first, isNull);
    expect(retried?.xpAwarded, 10);
    expect(provider.awardStatus, GameAwardStatus.awarded);
    expect(repository.completionCalls, 2);
  });

  test('completion cannot be submitted twice while in flight', () async {
    final repository = _FakeGamesRepository()
      ..pendingCompletion = Completer<XPAwardResult>();
    final provider = GamesProvider(repository: repository);

    final first = provider.completeGame(
      gameType: GameType.wordScramble,
      score: 1,
      totalQuestions: 1,
      correctAnswers: 1,
      answers: _answers,
      sessionId: 'session-1',
    );
    final second = await provider.completeGame(
      gameType: GameType.wordScramble,
      score: 1,
      totalQuestions: 1,
      correctAnswers: 1,
      answers: _answers,
      sessionId: 'session-1',
    );

    expect(second, isNull);
    expect(repository.completionCalls, 1);
    repository.pendingCompletion!.complete(_award);
    expect((await first)?.xpAwarded, 10);
  });

  test('already awarded completion returns cached result', () async {
    final repository = _FakeGamesRepository(outcomes: [_award]);
    final provider = GamesProvider(repository: repository);

    await provider.completeGame(
      gameType: GameType.wordScramble,
      score: 1,
      totalQuestions: 1,
      correctAnswers: 1,
      answers: _answers,
      sessionId: 'session-1',
    );
    final repeated = await provider.completeGame(
      gameType: GameType.wordScramble,
      score: 1,
      totalQuestions: 1,
      correctAnswers: 1,
      answers: _answers,
      sessionId: 'session-1',
    );

    expect(repeated?.xpAwarded, 10);
    expect(provider.awardStatus, GameAwardStatus.alreadyAwarded);
    expect(repository.completionCalls, 1);
  });
}
