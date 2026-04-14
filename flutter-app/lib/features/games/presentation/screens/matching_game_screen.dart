import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';

/// Matching Game screen.
///
/// Two columns: words (left) and definitions/matches (right).
/// Player taps a word then taps its match. Correct pairs disappear with green
/// flash; wrong pairs shake red and apply a penalty.
class MatchingGameScreen extends StatefulWidget {
  const MatchingGameScreen({super.key});

  @override
  State<MatchingGameScreen> createState() => _MatchingGameScreenState();
}

class _MatchingGameScreenState extends State<MatchingGameScreen> {
  late ConfettiController _confettiController;
  Timer? _timer;
  int _timeLeft = 45;
  bool _gameLoaded = false;
  String? _selectedWord; // Word column selection (pair id)
  String? _selectedMatch; // Match column selection
  Set<String> _matchedIds = {};
  Map<String, _PairState> _matchState = {};
  int _correctCount = 0;
  int _wrongPenalty = 0;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamesProvider>().loadMatchingGame().then((_) {
        if (mounted) _initGame();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  void _initGame() {
    final game = context.read<GamesProvider>().matching;
    if (game == null) return;
    setState(() {
      _gameLoaded = true;
      _timeLeft = game.timerSeconds;
      _matchedIds = {};
      _matchState = {};
      _selectedWord = null;
      _selectedMatch = null;
    });
    _startTimer(game.timerSeconds);
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _timeLeft--);
      if (_timeLeft <= 0) {
        t.cancel();
        _finishGame();
      }
    });
  }

  void _selectWord(String pairId) {
    if (_matchedIds.contains(pairId)) return;
    setState(() {
      _selectedWord = pairId;
      _selectedMatch = null;
    });
  }

  void _selectMatchItem(String matchText) {
    if (_selectedWord == null) return;
    final game = context.read<GamesProvider>().matching!;
    final pair = game.pairs.firstWhere((p) => p.wordId == _selectedWord);
    final correctMatch = pair.matchText;

    if (matchText == correctMatch) {
      _correctCount++;
      setState(() {
        _matchedIds.add(_selectedWord!);
        _matchState[_selectedWord!] = _PairState.correct;
        _selectedWord = null;
        _selectedMatch = null;
      });
      // All pairs matched → celebrate + finish (skill: gamification-confetti-win)
      if (_matchedIds.length == game.pairs.length) {
        _confettiController.play();
        _timer?.cancel();
        Future.delayed(const Duration(milliseconds: 800), _finishGame);
      }
    } else {
      // Wrong — shake effect
      setState(() {
        _selectedMatch = matchText;
        _matchState[_selectedWord!] = _PairState.wrong;
      });
      _wrongPenalty++;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _matchState.remove(_selectedWord);
            _selectedWord = null;
            _selectedMatch = null;
          });
        }
      });
    }
  }

  void _finishGame() async {
    _timer?.cancel();
    final provider = context.read<GamesProvider>();
    final game = provider.matching!;
    final total = game.pairs.length;

    final elapsed = game.timerSeconds - _timeLeft;
    // Time bonus: +5 XP if finished in less than 50% of total time
    // (skill: progress-xp-system → time-bonus)
    final timeBonusXp = (elapsed < game.timerSeconds * game.timeBonusThreshold)
        ? 5
        : 0;
    final rawXp = game.baseXp - (_wrongPenalty * 2) + timeBonusXp;
    final finalXp = rawXp.clamp(0, game.baseXp + 5);

    final xpResult = await provider.completeGame(
      gameType: GameType.matching,
      score: _correctCount,
      totalQuestions: total,
      correctAnswers: _correctCount,
      baseXp: finalXp,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: GameResult(
            gameType: GameType.matching,
            cefrLevel: provider.selectedLevel,
            score: _correctCount,
            totalQuestions: total,
            correctAnswers: _correctCount,
            xpEarned: xpResult?.xpAwarded ?? finalXp,
            durationSeconds: elapsed,
            xpResult: xpResult,
          ),
          xpResult: xpResult,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GamesProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading || !_gameLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final game = provider.matching!;
        final remaining = game.pairs
            .where((p) => !_matchedIds.contains(p.wordId))
            .toList();

        return Scaffold(
          backgroundColor: AppColors.backgroundLight,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: const Text(
              'Matching Game',
              style: TextStyle(color: AppColors.textDark),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _TimerChip(
                  timeLeft: _timeLeft,
                  total: game.timerSeconds,
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _matchedIds.length / game.pairs.length,
                    backgroundColor: AppColors.grey200,
                    color: AppColors.greenSuccess,
                    minHeight: 4,
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      '${_matchedIds.length}/${game.pairs.length} matched',
                      style: const TextStyle(
                        color: AppColors.textGrey,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          // Words column
                          Expanded(
                            child: _ColumnList(
                              items: remaining.map((p) => p.word).toList(),
                              selectedItem: _selectedWord != null
                                  ? game.pairs
                                        .firstWhere(
                                          (p) => p.wordId == _selectedWord,
                                        )
                                        .word
                                  : null,
                              pairStates: Map.fromEntries(
                                remaining.map(
                                  (p) =>
                                      MapEntry(p.word, _matchState[p.wordId]),
                                ),
                              ),
                              onTap: (word) {
                                final p = game.pairs.firstWhere(
                                  (p) => p.word == word,
                                );
                                _selectWord(p.wordId);
                              },
                              label: 'Words',
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Matches column
                          Expanded(
                            child: _ColumnList(
                              items: game.matchesColumn
                                  .where(
                                    (m) => !_matchedIds.any((id) {
                                      try {
                                        return game.pairs
                                                .firstWhere(
                                                  (p) => p.wordId == id,
                                                )
                                                .matchText ==
                                            m;
                                      } catch (_) {
                                        return false;
                                      }
                                    }),
                                  )
                                  .toList(),
                              selectedItem: _selectedMatch,
                              pairStates: const {},
                              onTap: _selectMatchItem,
                              label: game.variation == 'definition'
                                  ? 'Definitions'
                                  : 'Matches',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Confetti overlay (skill: gamification-confetti-win)
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confettiController,
                  blastDirectionality: BlastDirectionality.explosive,
                  numberOfParticles: 20,
                  gravity: 0.4,
                  colors: const [
                    AppColors.primary,
                    Colors.yellow,
                    Colors.green,
                    AppColors.orange,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _PairState { correct, wrong }

class _ColumnList extends StatelessWidget {
  final List<String> items;
  final String? selectedItem;
  final Map<String, _PairState?> pairStates;
  final ValueChanged<String> onTap;
  final String label;

  const _ColumnList({
    required this.items,
    required this.selectedItem,
    required this.pairStates,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: AppColors.textGrey,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              final selected = selectedItem == item;
              final state = pairStates[item];
              Color bg = Colors.white;
              Color border = AppColors.grey300;
              if (selected) {
                bg = AppColors.primary.withValues(alpha: 0.1);
                border = AppColors.primary;
              }
              if (state == _PairState.correct) {
                bg = AppColors.greenSuccess.withValues(alpha: 0.15);
                border = AppColors.greenSuccess;
              }
              if (state == _PairState.wrong) {
                bg = Colors.red.withValues(alpha: 0.1);
                border = Colors.red;
              }
              return GestureDetector(
                onTap: () => onTap(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: border, width: 1.5),
                  ),
                  child: Text(
                    item,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textDark,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TimerChip extends StatelessWidget {
  final int timeLeft;
  final int total;
  const _TimerChip({required this.timeLeft, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? timeLeft / total : 0.0;
    final color = ratio > 0.5
        ? AppColors.greenSuccess
        : ratio > 0.25
        ? AppColors.orange
        : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        '${timeLeft}s',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 14,
        ),
      ),
    );
  }
}
