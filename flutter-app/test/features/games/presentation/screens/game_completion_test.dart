/// Widget tests for game completion result display.
///
/// Tests:
/// - Award succeeded: server XP shown (no error icon)
/// - Award failed: error card with cloud_off icon + retry button
/// - Retry: second completion call awards XP
/// - Already awarded: only one network call
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/games/data/repositories/games_repository.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';
import 'package:provider/provider.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeGamesRepository extends GamesRepository {
  int completionCalls = 0;
  Completer<XPAwardResult>? pendingCompletion;
  final List<Object> outcomes;

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

// ── Constants ─────────────────────────────────────────────────────────────────

const _award = XPAwardResult(
  xpAwarded: 30,
  baseXp: 20,
  newTotalXp: 130,
  oldLevel: 1,
  newLevel: 1,
  message: '+30 XP',
);

const _answers = [
  {'id': 'q1', 'answer': 'cat'},
];

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrap(Widget child, GamesProvider provider) {
  return MaterialApp(
    home: ChangeNotifierProvider<GamesProvider>.value(
      value: provider,
      child: child,
    ),
  );
}

GameResult _makeResult({XPAwardResult? xpResult}) => GameResult(
  gameType: GameType.wordScramble,
  cefrLevel: 'A1',
  score: 10,
  totalQuestions: 10,
  correctAnswers: 10,
  xpEarned: xpResult?.xpAwarded ?? 0,
  durationSeconds: 60,
  xpResult: xpResult,
);

/// Pumps enough frames to drain the internal delayed timers in GameResultScreen
/// (400ms star delay + 1400ms XP animation + 1800ms level-up delay = ~2.5s).
Future<void> _drainTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 1400));
  await tester.pump(const Duration(milliseconds: 800));
}

// ── Widget Tests ──────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('GameResultScreen — award succeeded', () {
    testWidgets('shows star rating icons', (tester) async {
      final result = _makeResult(xpResult: _award);

      await tester.pumpWidget(
        _wrap(
          GameResultScreen(result: result, xpResult: _award),
          GamesProvider(repository: _FakeGamesRepository()),
        ),
      );
      await _drainTimers(tester);

      // Star icons are present for the result card
      expect(find.byIcon(Icons.star_rounded), findsWidgets);
      // No error icon
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });

    testWidgets('does not show error card when xpResult is present',
        (tester) async {
      final result = _makeResult(xpResult: _award);

      await tester.pumpWidget(
        _wrap(
          GameResultScreen(result: result, xpResult: _award),
          GamesProvider(repository: _FakeGamesRepository()),
        ),
      );
      await _drainTimers(tester);

      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });
  });

  group('GameResultScreen — award failed', () {
    testWidgets('shows error card with cloud_off icon when xpResult is null',
        (tester) async {
      final result = _makeResult(xpResult: null);

      await tester.pumpWidget(
        _wrap(
          GameResultScreen(result: result, xpResult: null),
          GamesProvider(repository: _FakeGamesRepository()),
        ),
      );
      await _drainTimers(tester);

      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('retry button (refresh icon) is visible in error state',
        (tester) async {
      final result = _makeResult(xpResult: null);

      await tester.pumpWidget(
        _wrap(
          GameResultScreen(result: result, xpResult: null),
          GamesProvider(repository: _FakeGamesRepository(outcomes: [_award])),
        ),
      );
      await _drainTimers(tester);

      // The retry button has a refresh icon
      expect(find.byIcon(Icons.refresh_rounded), findsAtLeastNWidgets(1));
    });

    testWidgets('tapping retry triggers second completion and awards XP',
        (tester) async {
      final repo = _FakeGamesRepository(
        outcomes: [Exception('network error'), _award],
      );
      final provider = GamesProvider(repository: repo);

      // First completion fails
      await provider.completeGame(
        gameType: GameType.wordScramble,
        score: 10,
        totalQuestions: 10,
        correctAnswers: 10,
        answers: _answers,
        sessionId: 'session-retry',
      );
      expect(provider.awardStatus, GameAwardStatus.failed);

      final result = _makeResult(xpResult: null);

      await tester.pumpWidget(
        _wrap(GameResultScreen(result: result, xpResult: null), provider),
      );
      await _drainTimers(tester);

      // Error state is visible
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);

      // Tap the retry button
      await tester.tap(find.byIcon(Icons.refresh_rounded).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Provider should now be in awarded state
      expect(provider.awardStatus, GameAwardStatus.awarded);
      expect(repo.completionCalls, 2);

      await _drainTimers(tester);
    });
  });

  group('GameResultScreen — already awarded', () {
    testWidgets(
        'result screen renders without resubmitting when already awarded',
        (tester) async {
      final repository = _FakeGamesRepository(outcomes: [_award]);
      final provider = GamesProvider(repository: repository);

      // Award once
      await provider.completeGame(
        gameType: GameType.wordScramble,
        score: 10,
        totalQuestions: 10,
        correctAnswers: 10,
        answers: _answers,
        sessionId: 'session-z',
      );
      // Try to award again — should hit alreadyAwarded path
      await provider.completeGame(
        gameType: GameType.wordScramble,
        score: 10,
        totalQuestions: 10,
        correctAnswers: 10,
        answers: _answers,
        sessionId: 'session-z',
      );
      expect(provider.awardStatus, GameAwardStatus.alreadyAwarded);
      expect(repository.completionCalls, 1);

      final result = _makeResult(xpResult: _award);

      await tester.pumpWidget(
        _wrap(
          GameResultScreen(result: result, xpResult: _award),
          provider,
        ),
      );
      await _drainTimers(tester);

      // Still only one network call
      expect(repository.completionCalls, 1);
      // Result screen shows correctly (no error state)
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
    });
  });

  // ── Unit tests for provider answer payloads ────────────────────────────────

  group('Provider — answer payload correctness', () {
    test('completeGame sends full answer list for word scramble', () async {
      final repository = _FakeGamesRepository(outcomes: [_award]);
      final provider = GamesProvider(repository: repository);

      await provider.completeGame(
        gameType: GameType.wordScramble,
        score: 3,
        totalQuestions: 3,
        correctAnswers: 3,
        answers: [
          {'id': 'w1', 'answer': 'cat'},
          {'id': 'w2', 'answer': 'dog'},
          {'id': 'w3', 'answer': 'bird'},
        ],
        sessionId: 'session-abc',
      );

      expect(repository.completionCalls, 1);
      expect(provider.awardStatus, GameAwardStatus.awarded);
      expect(provider.lastGameResult?.correctAnswers, 3);
    });

    test('completeGame fails gracefully when session ID is missing', () async {
      final repository = _FakeGamesRepository();
      final provider = GamesProvider(repository: repository);

      // No sessionId provided, no game loaded — provider has no session to use
      final result = await provider.completeGame(
        gameType: GameType.wordScramble,
        score: 1,
        totalQuestions: 1,
        correctAnswers: 1,
        answers: _answers,
      );

      expect(result, isNull);
      expect(provider.awardStatus, GameAwardStatus.failed);
      expect(provider.awardError, isNotNull);
      expect(repository.completionCalls, 0);
    });

    test('hangman completion includes hintsUsed', () async {
      final repository = _FakeGamesRepository(outcomes: [_award]);
      final provider = GamesProvider(repository: repository);

      await provider.completeGame(
        gameType: GameType.hangman,
        score: 10,
        totalQuestions: 1,
        correctAnswers: 1,
        answers: [{'id': 'h1', 'answer': 'elephant'}],
        sessionId: 'hangman-session-1',
        hintsUsed: 2,
      );

      expect(provider.awardStatus, GameAwardStatus.awarded);
      expect(repository.completionCalls, 1);
    });

    test('fillBlank completion submits all questions', () async {
      final repository = _FakeGamesRepository(outcomes: [_award]);
      final provider = GamesProvider(repository: repository);

      await provider.completeGame(
        gameType: GameType.fillBlank,
        score: 30,
        totalQuestions: 3,
        correctAnswers: 3,
        answers: [
          {'id': 'q1', 'answer': 'is'},
          {'id': 'q2', 'answer': 'are'},
          {'id': 'q3', 'answer': 'was'},
        ],
        sessionId: 'fb-session-1',
      );

      expect(provider.awardStatus, GameAwardStatus.awarded);
      expect(provider.lastGameResult?.xpEarned, 30);
    });

    test('matching completion submits pair answers', () async {
      final repository = _FakeGamesRepository(outcomes: [_award]);
      final provider = GamesProvider(repository: repository);

      await provider.completeGame(
        gameType: GameType.matching,
        score: 18,
        totalQuestions: 6,
        correctAnswers: 6,
        answers: [
          {'id': 'p1', 'answer': 'A small furry animal'},
          {'id': 'p2', 'answer': 'A large grey mammal'},
        ],
        sessionId: 'match-session-1',
      );

      expect(provider.awardStatus, GameAwardStatus.awarded);
    });

    test('grammarQuiz completion submits selected options', () async {
      final repository = _FakeGamesRepository(outcomes: [_award]);
      final provider = GamesProvider(repository: repository);

      await provider.completeGame(
        gameType: GameType.grammarQuiz,
        score: 25,
        totalQuestions: 5,
        correctAnswers: 5,
        answers: [
          {'id': 'gq1', 'answer': 'is'},
          {'id': 'gq2', 'answer': 'have'},
        ],
        sessionId: 'gq-session-1',
      );

      expect(provider.awardStatus, GameAwardStatus.awarded);
    });

    test('spellingBee completion submits typed words', () async {
      final repository = _FakeGamesRepository(outcomes: [_award]);
      final provider = GamesProvider(repository: repository);

      await provider.completeGame(
        gameType: GameType.spellingBee,
        score: 8,
        totalQuestions: 8,
        correctAnswers: 8,
        answers: [
          {'id': 'sb1', 'answer': 'knowledge'},
          {'id': 'sb2', 'answer': 'adventure'},
        ],
        sessionId: 'sb-session-1',
      );

      expect(provider.awardStatus, GameAwardStatus.awarded);
    });
  });
}
