import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/hangman_figure.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_load_state.dart';

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
  bool _isFinishing = false;

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
    if (_wrongGuesses >= game.maxLives) {
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
    if (_isFinishing) return;
    _isFinishing = true;
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final provider = context.read<GamesProvider>();
    final correctAnswers = _gameWon ? 1 : 0;
    final xpResult = await provider.completeGame(
      gameType: GameType.hangman,
      score: correctAnswers,
      totalQuestions: 1,
      correctAnswers: correctAnswers,
      answers: [
        {
          'id': game.wordId,
          'answer': _gameWon ? game.word : '',
        },
      ],
      hintsUsed: (_hint2Used ? 1 : 0) + (_hint3Used ? 1 : 0),
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
            xpEarned: xpResult?.xpAwarded ?? 0,
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
            if (provider.isLoading) {
              return const Scaffold(
                body: Center(child: LottieLoadingWidget.medium()),
              );
            }
            final game = provider.hangman;
            if (provider.error != null) {
              return GameLoadState(
                message: 'games.loadFailed'.tr(),
                onRetry: () async {
                  await provider.loadHangman();
                  if (!mounted) return;
                  final loaded = provider.hangman;
                  if (loaded != null) {
                    setState(() {
                      _gameLoaded = true;
                    });
                  }
                },
              );
            }
            if (game == null || game.word.isEmpty) {
              return GameLoadState(
                message: 'games.emptyGame'.tr(),
                onRetry: () async {
                  await provider.loadHangman();
                  if (!mounted) return;
                  final loaded = provider.hangman;
                  if (loaded != null) {
                    setState(() {
                      _gameLoaded = true;
                    });
                  }
                },
              );
            }
            if (!_gameLoaded) {
              return const Scaffold(
                body: Center(child: LottieLoadingWidget.medium()),
              );
            }
            final word = _wordLetters(game);

            return Scaffold(
              appBar: AppBar(
                backgroundColor: Theme.of(context).colorScheme.surface,
                elevation: 0,
                title: Text(
                  'hangman.title'.tr(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Row(
                      children: List.generate(
                        game.maxLives,
                        (i) => Icon(
                          Icons.favorite,
                          color: i < game.maxLives - _wrongGuesses
                              ? AppColors.errorBright
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
                            game.category.isEmpty
                                ? 'hangman.defaultCategory'.tr()
                                : game.category,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                            ),
                          ),
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          side: const BorderSide(color: AppColors.primary),
                        ),
                        const Spacer(),
                        Text(
                          'hangman.livesLeftLabel'.tr(
                            namedArgs: {
                              'lives': '${game.maxLives - _wrongGuesses}',
                            },
                          ),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
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
                                    : Theme.of(
                                        context,
                                      ).colorScheme.outlineVariant,
                                width: 2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: revealed
                              ? Text(
                                  letter,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
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
                        'hangman.wordRevealLabel'.tr(
                          namedArgs: {'word': game.word},
                        ),
                        style: const TextStyle(
                          color: AppColors.errorBright,
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
                          label: 'hangman.hint1Label'.tr(),
                          detail: 'hangman.hintFreeLabel'.tr(),
                          used: _hint1Used,
                          disabled: _gameOver,
                          onTap: () => _useHint1(game),
                          color: AppColors.greenSuccess,
                        ),
                        const SizedBox(width: 8),
                        _HintButton(
                          label: 'hangman.hint2Label'.tr(),
                          detail: '-${game.hints.hint2XpCost}XP',
                          used: _hint2Used,
                          disabled: _gameOver,
                          onTap: () => _useHint2(game),
                          color: AppColors.orange,
                        ),
                        const SizedBox(width: 8),
                        _HintButton(
                          label: 'hangman.hint3Label'.tr(),
                          detail: '-${game.hints.hint3XpCost}XP',
                          used: _hint3Used,
                          disabled: _gameOver,
                          onTap: () => _useHint3(game),
                          color: AppColors.purple,
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
          color: active
              ? color.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? color
                : Theme.of(context).colorScheme.outlineVariant,
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
                color: active
                    ? color
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              used ? 'hangman.hintUsedLabel'.tr() : detail,
              style: TextStyle(
                fontSize: 10,
                color: active
                    ? color.withValues(alpha: 0.7)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
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
            Color bg = Theme.of(context).colorScheme.surface;
            Color text = Theme.of(context).colorScheme.onSurface;
            Color border = Theme.of(context).colorScheme.outlineVariant;
            if (correct) {
              bg = AppColors.greenSuccess;
              text = Colors.white;
              border = AppColors.greenSuccess;
            } else if (wrong) {
              bg = Theme.of(context).colorScheme.surfaceContainerHighest;
              text = Theme.of(context).colorScheme.onSurfaceVariant;
              border = Theme.of(context).colorScheme.outlineVariant;
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
