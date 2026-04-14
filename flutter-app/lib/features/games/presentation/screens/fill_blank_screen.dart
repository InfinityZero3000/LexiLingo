import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';

/// Fill in the Blank game screen.
///
/// Shows a sentence with a missing word and 4 answer options in a 2×2 grid.
/// 15-second countdown per question with grammar tip feedback.
class FillBlankScreen extends StatefulWidget {
  const FillBlankScreen({super.key});

  @override
  State<FillBlankScreen> createState() => _FillBlankScreenState();
}

class _FillBlankScreenState extends State<FillBlankScreen> {
  late ConfettiController _confettiController;
  Timer? _timer;
  int _questionIndex = 0;
  int _timeLeft = 15;
  int _correctCount = 0;
  int? _selectedIndex;
  bool _answered = false;
  bool _gameLoaded = false;
  String? _feedbackTip;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamesProvider>().loadFillBlank().then((_) {
        if (mounted) _startQuestion();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  void _startQuestion() {
    final provider = context.read<GamesProvider>();
    final game = provider.fillBlank;
    if (game == null) return;
    final seconds = game.timerSecondsPerQuestion;
    setState(() {
      _gameLoaded = true;
      _timeLeft = seconds;
      _selectedIndex = null;
      _answered = false;
      _feedbackTip = null;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _timeLeft--);
      if (_timeLeft <= 0) {
        t.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (_answered) return;
    final game = context.read<GamesProvider>().fillBlank!;
    final q = game.questions[_questionIndex];
    setState(() {
      _answered = true;
      _feedbackTip = q.explanation.isNotEmpty ? q.explanation : 'Time\'s up!';
    });
    Future.delayed(const Duration(seconds: 2), _nextQuestion);
  }

  void _selectAnswer(int index) {
    if (_answered) return;
    _timer?.cancel();
    final game = context.read<GamesProvider>().fillBlank!;
    final q = game.questions[_questionIndex];
    final correct = q.options[index] == q.correctAnswer;
    if (correct) _correctCount++;
    setState(() {
      _selectedIndex = index;
      _answered = true;
      _feedbackTip = correct
          ? (q.grammarTip.isNotEmpty ? q.grammarTip : 'Correct!')
          : (q.explanation.isNotEmpty ? q.explanation : 'Incorrect.');
    });
    Future.delayed(const Duration(seconds: 2), _nextQuestion);
  }

  void _nextQuestion() {
    final game = context.read<GamesProvider>().fillBlank;
    if (game == null) return;
    if (_questionIndex + 1 >= game.questions.length) {
      _finishGame();
      return;
    }
    setState(() => _questionIndex++);
    _startQuestion();
  }

  void _finishGame() async {
    _timer?.cancel();
    final provider = context.read<GamesProvider>();
    final game = provider.fillBlank!;
    // Celebrate if pass rate ≥ 60% (skill: gamification-confetti-win)
    if (game.questions.isNotEmpty &&
        _correctCount / game.questions.length >= 0.6) {
      _confettiController.play();
      await Future.delayed(const Duration(milliseconds: 1200));
    }
    if (!mounted) return;
    final xpResult = await provider.completeGame(
      gameType: GameType.fillBlank,
      score: _correctCount,
      totalQuestions: game.questions.length,
      correctAnswers: _correctCount,
      baseXp: game.totalXp,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: GameResult(
            gameType: GameType.fillBlank,
            cefrLevel: provider.selectedLevel,
            score: _correctCount,
            totalQuestions: game.questions.length,
            correctAnswers: _correctCount,
            xpEarned: xpResult?.xpAwarded ?? game.totalXp,
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
    return Consumer<GamesProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading || !_gameLoaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final game = provider.fillBlank!;
        final q = game.questions[_questionIndex];

        return Scaffold(
          backgroundColor: AppColors.backgroundLight,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'Question ${_questionIndex + 1}/${game.questions.length}',
              style: const TextStyle(color: AppColors.textDark),
            ),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Progress bar
                  LinearProgressIndicator(
                    value: (_questionIndex) / game.questions.length,
                    backgroundColor: AppColors.grey200,
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                  // Timer bar
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 16,
                          color: AppColors.textGrey,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _timeLeft / game.timerSecondsPerQuestion,
                            backgroundColor: AppColors.grey200,
                            color: _timeLeft > 5
                                ? AppColors.primary
                                : Colors.red,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_timeLeft}s',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _timeLeft > 5
                                ? AppColors.textGrey
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Question sentence
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              q.sentence,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Options grid
                          GridView.count(
                            physics: const NeverScrollableScrollPhysics(),
                            shrinkWrap: true,
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 2.4,
                            children: List.generate(q.options.length, (i) {
                              Color bg = Colors.white;
                              Color border = AppColors.grey300;
                              Color text = AppColors.textDark;
                              if (_answered) {
                                if (q.options[i] == q.correctAnswer) {
                                  bg = AppColors.greenSuccess.withValues(alpha: 0.1);
                                  border = AppColors.greenSuccess;
                                  text = AppColors.greenSuccess;
                                } else if (i == _selectedIndex) {
                                  bg = Colors.red.withValues(alpha: 0.1);
                                  border = Colors.red;
                                  text = Colors.red;
                                }
                              } else if (_selectedIndex == i) {
                                bg = AppColors.primary.withValues(alpha: 0.1);
                                border = AppColors.primary;
                                text = AppColors.primary;
                              }
                              return GestureDetector(
                                onTap: () => _selectAnswer(i),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: border,
                                      width: 1.5,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    q.options[i],
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: text,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }),
                          ),
                          // Feedback tip
                          if (_feedbackTip != null) ...[
                            const SizedBox(height: 16),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color:
                                    _answered &&
                                        _selectedIndex != null &&
                                        q.options[_selectedIndex!] ==
                                            q.correctAnswer
                                    ? AppColors.greenSuccess.withValues(alpha: 0.1)
                                    : Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      _answered &&
                                          _selectedIndex != null &&
                                          q.options[_selectedIndex!] ==
                                              q.correctAnswer
                                      ? AppColors.greenSuccess
                                      : Colors.red,
                                ),
                              ),
                              child: Text(
                                _feedbackTip!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textDark,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              // Confetti overlay — fires on win (skill: gamification-confetti-win)
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
