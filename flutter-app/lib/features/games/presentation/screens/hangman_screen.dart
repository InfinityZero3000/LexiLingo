import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/hangman_figure.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';

/// Classic Hangman game screen.
///
/// On-screen A-Z keyboard, progressive figure drawing, 3 hint levels,
/// win/lose animations.
class HangmanScreen extends StatefulWidget {
  const HangmanScreen({super.key});

  @override
  State<HangmanScreen> createState() => _HangmanScreenState();
}

class _HangmanScreenState extends State<HangmanScreen>
    with TickerProviderStateMixin {
  late ConfettiController _confettiController;

  int _wrongGuesses = 0;
  final Set<String> _guessedLetters = {};
  bool _gameLoaded = false;
  bool _gameOver = false;
  bool _gameWon = false;
  bool _hint1Used = false;
  bool _hint2Used = false;
  bool _hint3Used = false;
  String? _revealedHint;
  int _xpEarned = 0;

  static const int maxWrong = 6;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 3),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamesProvider>().loadHangman().then((_) {
        if (mounted) {
          final game = context.read<GamesProvider>().hangman;
          if (game != null) {
            setState(() {
              _gameLoaded = true;
              _xpEarned = game.baseXp;
            });
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  List<String> _wordLetters(HangmanGame game) =>
      game.word.toUpperCase().split('');

  bool _isWordGuessed(HangmanGame game) {
    return _wordLetters(
      game,
    ).where((l) => l != ' ').every((l) => _guessedLetters.contains(l));
  }

  void _guessLetter(String letter, HangmanGame game) {
    if (_gameOver || _guessedLetters.contains(letter)) return;
    final word = _wordLetters(game);
    setState(() {
      _guessedLetters.add(letter);
      if (!word.contains(letter)) {
        _wrongGuesses++;
      }
    });
    if (_wrongGuesses >= maxWrong) {
      setState(() {
        _gameOver = true;
        _gameWon = false;
      });
      _finishGame(game);
    } else if (_isWordGuessed(game)) {
      setState(() {
        _gameOver = true;
        _gameWon = true;
      });
      _confettiController.play();
      _finishGame(game);
    }
  }

  void _useHint1(HangmanGame game) {
    if (_hint1Used) return;
    setState(() {
      _hint1Used = true;
      _revealedHint = game.hints.hint1Free;
    });
  }

  void _useHint2(HangmanGame game) {
    if (_hint2Used) return;
    setState(() {
      _hint2Used = true;
      _xpEarned -= game.hints.hint2XpCost;
      _revealedHint = game.hints.hint2Definition;
    });
  }

  void _useHint3(HangmanGame game) {
    if (_hint3Used) return;
    // Reveal a random unguessed letter
    final word = _wordLetters(game);
    final unguessed = word
        .where((l) => l != ' ' && !_guessedLetters.contains(l))
        .toList();
    if (unguessed.isEmpty) return;
    unguessed.shuffle();
    setState(() {
      _hint3Used = true;
      _xpEarned -= game.hints.hint3XpCost;
      _guessedLetters.add(unguessed.first);
    });
    if (_isWordGuessed(game)) {
      setState(() {
        _gameOver = true;
        _gameWon = true;
      });
      _confettiController.play();
      _finishGame(game);
    }
  }

  Future<void> _finishGame(HangmanGame game) async {
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final provider = context.read<GamesProvider>();
    final correctAnswers = _gameWon ? 1 : 0;
    final xpResult = await provider.completeGame(
      gameType: GameType.hangman,
      score: correctAnswers,
      totalQuestions: 1,
      correctAnswers: correctAnswers,
      baseXp: _xpEarned.clamp(0, game.baseXp),
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: GameResult(
            gameType: GameType.hangman,
            cefrLevel: provider.selectedLevel,
            score: correctAnswers,
            totalQuestions: 1,
            correctAnswers: correctAnswers,
            xpEarned: xpResult?.xpAwarded ?? _xpEarned.clamp(0, game.baseXp),
            durationSeconds: 0,
            xpResult: xpResult,
          ),
          xpResult: xpResult,
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
            final game = provider.hangman!;
            final word = _wordLetters(game);

            return Scaffold(
              backgroundColor: AppColors.backgroundLight,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                title: const Text(
                  'Hangman',
                  style: TextStyle(color: AppColors.textDark),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      children: List.generate(
                        maxWrong,
                        (i) => Icon(
                          Icons.favorite,
                          color: i < maxWrong - _wrongGuesses
                              ? Colors.red
                              : AppColors.grey300,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              body: Column(
                children: [
                  // Category chip
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      children: [
                        Chip(
                          label: Text(
                            game.category.isEmpty ? 'General' : game.category,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          side: const BorderSide(color: AppColors.primary),
                        ),
                        const Spacer(),
                        Text(
                          '${maxWrong - _wrongGuesses} lives left',
                          style: const TextStyle(
                            color: AppColors.textGrey,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Hangman figure
                  HangmanFigure(wrongGuesses: _wrongGuesses),
                  const SizedBox(height: 8),
                  // Hint reveal
                  if (_revealedHint != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accentYellow.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.accentYellow),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 14,
                              color: AppColors.accentYellow,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _revealedHint!,
                                style: const TextStyle(fontSize: 13),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Word blanks
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 4,
                      children: word.map((letter) {
                        if (letter == ' ') {
                          return const SizedBox(width: 16);
                        }
                        final revealed = _guessedLetters.contains(letter);
                        return Container(
                          width: 30,
                          height: 38,
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: revealed
                                    ? AppColors.primary
                                    : AppColors.textGrey,
                                width: 2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: revealed
                              ? Text(
                                  letter,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: AppColors.textDark,
                                  ),
                                )
                              : null,
                        );
                      }).toList(),
                    ),
                  ),
                  // Lose reveal
                  if (_gameOver && !_gameWon)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'The word was: ${game.word}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Hint buttons
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _HintButton(
                          label: 'Hint 1',
                          detail: 'Free',
                          used: _hint1Used,
                          disabled: _gameOver,
                          onTap: () => _useHint1(game),
                          color: AppColors.greenSuccess,
                        ),
                        const SizedBox(width: 8),
                        _HintButton(
                          label: 'Hint 2',
                          detail: '-${game.hints.hint2XpCost}XP',
                          used: _hint2Used,
                          disabled: _gameOver,
                          onTap: () => _useHint2(game),
                          color: Colors.orange,
                        ),
                        const SizedBox(width: 8),
                        _HintButton(
                          label: 'Hint 3',
                          detail: '-${game.hints.hint3XpCost}XP',
                          used: _hint3Used,
                          disabled: _gameOver,
                          onTap: () => _useHint3(game),
                          color: Colors.purple,
                        ),
                      ],
                    ),
                  ),
                  // Keyboard
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _Keyboard(
                        guessedLetters: _guessedLetters,
                        wordLetters: word.toSet(),
                        gameOver: _gameOver,
                        onTap: (l) => _guessLetter(l, game),
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
          numberOfParticles: 25,
          gravity: 0.3,
          colors: const [
            AppColors.primary,
            AppColors.accentYellow,
            AppColors.greenSuccess,
            Colors.pink,
          ],
        ),
      ],
    );
  }
}

class _HintButton extends StatelessWidget {
  final String label;
  final String detail;
  final bool used;
  final bool disabled;
  final VoidCallback onTap;
  final Color color;

  const _HintButton({
    required this.label,
    required this.detail,
    required this.used,
    required this.disabled,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final active = !used && !disabled;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.1) : AppColors.grey200,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? color : AppColors.grey300,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: active ? color : AppColors.textGrey,
              ),
            ),
            Text(
              used ? 'Used' : detail,
              style: TextStyle(
                fontSize: 10,
                color: active ? color.withValues(alpha: 0.7) : AppColors.textGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Keyboard extends StatelessWidget {
  final Set<String> guessedLetters;
  final Set<String> wordLetters;
  final bool gameOver;
  final ValueChanged<String> onTap;

  const _Keyboard({
    required this.guessedLetters,
    required this.wordLetters,
    required this.gameOver,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'],
      ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'],
      ['Z', 'X', 'C', 'V', 'B', 'N', 'M'],
    ];
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: rows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((letter) {
            final guessed = guessedLetters.contains(letter);
            final correct = guessed && wordLetters.contains(letter);
            final wrong = guessed && !wordLetters.contains(letter);
            Color bg = Colors.white;
            Color text = AppColors.textDark;
            Color border = AppColors.grey300;
            if (correct) {
              bg = AppColors.greenSuccess;
              text = Colors.white;
              border = AppColors.greenSuccess;
            } else if (wrong) {
              bg = AppColors.grey200;
              text = AppColors.textGrey;
              border = AppColors.grey300;
            }
            return GestureDetector(
              onTap: (!guessed && !gameOver) ? () => onTap(letter) : null,
              child: Container(
                width: 32,
                height: 36,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: border),
                ),
                alignment: Alignment.center,
                child: Text(
                  letter,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: text,
                  ),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
