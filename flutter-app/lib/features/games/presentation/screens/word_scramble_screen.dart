import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/letter_tile.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';

/// Word Scramble game screen.
///
/// Presents one word at a time with shuffled letter tiles. The player taps
/// tiles to build the answer. Includes a timer and hint button.
class WordScrambleScreen extends StatefulWidget {
  const WordScrambleScreen({super.key});

  @override
  State<WordScrambleScreen> createState() => _WordScrambleScreenState();
}

class _WordScrambleScreenState extends State<WordScrambleScreen> {
  late ConfettiController _confettiController;
  Timer? _timer;

  int _currentWordIndex = 0;
  int _timeLeft = 60;
  int _correctCount = 0;
  int _totalXpEarned = 0;
  bool _gameLoaded = false;
  bool _showHint = false;
  bool _wordAnswered = false;
  String? _xpPopup;

  // Letter tile state
  List<String> _poolLetters = []; // Available pool
  List<String?> _answerSlots = []; // Filled answer slots (null = empty)
  List<bool> _slotCorrect = [];
  List<bool> _slotWrong = [];

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 1),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamesProvider>().loadWordScramble().then((_) {
        if (mounted) _initWord();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  void _initWord() {
    final game = context.read<GamesProvider>().wordScramble;
    if (game == null || _currentWordIndex >= game.words.length) return;
    final word = game.words[_currentWordIndex];
    setState(() {
      _gameLoaded = true;
      _poolLetters = List<String>.from(word.shuffledLetters);
      _answerSlots = List<String?>.filled(
        word.letterCount > 0 ? word.letterCount : word.word.length,
        null,
      );
      _slotCorrect = List<bool>.filled(_answerSlots.length, false);
      _slotWrong = List<bool>.filled(_answerSlots.length, false);
      _showHint = false;
      _wordAnswered = false;
      _xpPopup = null;
      _timeLeft = game.timerSeconds;
    });
    _startTimer(game.timerSeconds);
  }

  void _startTimer(int seconds) {
    _timer?.cancel();
    _timeLeft = seconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _timeLeft--);
      if (_timeLeft <= 0) {
        t.cancel();
        _skipWord();
      }
    });
  }

  void _tapPool(int index) {
    if (_wordAnswered) return;
    final letter = _poolLetters[index];
    final slotIdx = _answerSlots.indexWhere((s) => s == null);
    if (slotIdx == -1) return;
    setState(() {
      _poolLetters[index] = '';
      _answerSlots[slotIdx] = letter;
    });
    _checkAnswer();
  }

  void _tapSlot(int index) {
    if (_wordAnswered) return;
    final letter = _answerSlots[index];
    if (letter == null || letter.isEmpty) return;
    final poolIdx = _poolLetters.indexWhere((l) => l.isEmpty);
    setState(() {
      _answerSlots[index] = null;
      if (poolIdx != -1) {
        _poolLetters[poolIdx] = letter;
      } else {
        _poolLetters.add(letter);
      }
    });
  }

  void _checkAnswer() {
    if (_answerSlots.any((s) => s == null)) return;
    final game = context.read<GamesProvider>().wordScramble;
    if (game == null) return;
    final word = game.words[_currentWordIndex];
    final answer = _answerSlots.join().toLowerCase();
    final correct = word.word.toLowerCase();

    if (answer == correct) {
      _timer?.cancel();
      _correctCount++;
      _totalXpEarned += word.xpValue;
      setState(() {
        _slotCorrect = List<bool>.filled(_answerSlots.length, true);
        _wordAnswered = true;
        _xpPopup = '+${word.xpValue} XP';
      });
      _confettiController.play();
      Future.delayed(const Duration(milliseconds: 1400), _nextWord);
    } else if (_answerSlots.every((s) => s != null)) {
      setState(() {
        _slotWrong = List<bool>.filled(_answerSlots.length, true);
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _slotWrong = List<bool>.filled(_answerSlots.length, false);
          });
        }
      });
    }
  }

  void _nextWord() {
    final game = context.read<GamesProvider>().wordScramble;
    if (game == null) return;
    if (_currentWordIndex + 1 >= game.words.length) {
      _finishGame();
      return;
    }
    setState(() => _currentWordIndex++);
    _initWord();
  }

  void _skipWord() {
    _nextWord();
  }

  void _finishGame() async {
    _timer?.cancel();
    final provider = context.read<GamesProvider>();
    final game = provider.wordScramble;
    final xpResult = await provider.completeGame(
      gameType: GameType.wordScramble,
      score: _correctCount,
      totalQuestions: game?.words.length ?? 0,
      correctAnswers: _correctCount,
      baseXp: _totalXpEarned,
    );
    if (!mounted) return;
    final result = GameResult(
      gameType: GameType.wordScramble,
      cefrLevel: provider.selectedLevel,
      score: _correctCount,
      totalQuestions: game?.words.length ?? 0,
      correctAnswers: _correctCount,
      xpEarned: xpResult?.xpAwarded ?? _totalXpEarned,
      durationSeconds: 0,
      xpResult: xpResult,
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: result,
          xpResult: xpResult,
          onPlayAgain: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Consumer<GamesProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading || !_gameLoaded) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            final game = provider.wordScramble!;
            final word = game.words[_currentWordIndex];
            return Scaffold(
              backgroundColor: AppColors.backgroundLight,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                title: Text(
                  'Word ${_currentWordIndex + 1} of ${game.words.length}',
                  style: const TextStyle(color: AppColors.textDark),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Center(
                      child: _TimerDisplay(
                        timeLeft: _timeLeft,
                        total: game.timerSeconds,
                      ),
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  // Progress bar
                  LinearProgressIndicator(
                    value: (_currentWordIndex) / game.words.length,
                    backgroundColor: AppColors.grey200,
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        children: [
                          // XP popup
                          if (_xpPopup != null) _XpPopup(text: _xpPopup!),
                          const SizedBox(height: 4),
                          // Hint area
                          _HintCard(word: word, showHint: _showHint),
                          const SizedBox(height: 20),
                          // Answer slots
                          const Text(
                            'Your answer:',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: List.generate(_answerSlots.length, (i) {
                              return GestureDetector(
                                onTap: () => _tapSlot(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 42,
                                  height: 48,
                                  margin: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: _slotCorrect[i]
                                        ? AppColors.greenSuccess
                                        : _slotWrong[i]
                                        ? AppColors.errorDark
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _answerSlots[i] != null
                                          ? AppColors.primary
                                          : AppColors.grey300,
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _answerSlots[i]?.toUpperCase() ?? '',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: (_slotCorrect[i] || _slotWrong[i])
                                          ? Colors.white
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 24),
                          // Letter pool
                          const Text(
                            'Available letters:',
                            style: TextStyle(
                              color: AppColors.textGrey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: List.generate(_poolLetters.length, (i) {
                              final letter = _poolLetters[i];
                              if (letter.isEmpty) {
                                return const SizedBox(width: 50, height: 56);
                              }
                              return LetterTile(
                                key: ValueKey('pool_${i}_$letter'),
                                letter: letter,
                                onTap: () => _tapPool(i),
                              );
                            }),
                          ),
                          const Spacer(),
                          // Hint & Skip
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                onPressed: _wordAnswered
                                    ? null
                                    : () => setState(
                                        () => _showHint = !_showHint,
                                      ),
                                icon: const Icon(
                                  Icons.lightbulb_outline,
                                  size: 16,
                                ),
                                label: const Text('Hint'),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                  foregroundColor: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: _wordAnswered ? null : _skipWord,
                                child: const Text(
                                  'Skip',
                                  style: TextStyle(color: AppColors.textGrey),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        ConfettiWidget(
          confettiController: _confettiController,
          blastDirectionality: BlastDirectionality.explosive,
          numberOfParticles: 20,
          gravity: 0.4,
          emissionFrequency: 0.05,
          colors: const [
            AppColors.primary,
            AppColors.accentYellow,
            AppColors.greenSuccess,
          ],
        ),
      ],
    );
  }
}

class _TimerDisplay extends StatelessWidget {
  final int timeLeft;
  final int total;
  const _TimerDisplay({required this.timeLeft, required this.total});

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

class _HintCard extends StatelessWidget {
  final ScrambleWord word;
  final bool showHint;
  const _HintCard({required this.word, required this.showHint});

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: showHint && word.hint.isNotEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentYellow.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accentYellow),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    size: 14,
                    color: AppColors.accentYellow,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      word.hint,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

class _XpPopup extends StatelessWidget {
  final String text;
  const _XpPopup({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.greenSuccess,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
    );
  }
}
