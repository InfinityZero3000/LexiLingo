import 'dart:async';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';

/// Grammar Quiz game screen.
///
/// Similar to Fill in the Blank but shows the grammar topic, uses a 12-second
/// timer, and provides adaptive grammar mastery feedback.
class GrammarQuizScreen extends StatefulWidget {
  const GrammarQuizScreen({super.key});

  @override
  State<GrammarQuizScreen> createState() => _GrammarQuizScreenState();
}

class _GrammarQuizScreenState extends State<GrammarQuizScreen> {
  late ConfettiController _confettiController;
  Timer? _timer;
  int _questionIndex = 0;
  int _timeLeft = 12;
  int _correctCount = 0;
  int? _selectedIndex;
  bool _answered = false;
  bool _gameLoaded = false;
  String? _feedbackText;

  // Per-topic correct tracking for mastery message
  final Map<String, int> _topicCorrect = {};
  final Map<String, int> _topicTotal = {};

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 2),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamesProvider>().loadGrammarQuiz().then((_) {
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
    final game = context.read<GamesProvider>().grammarQuiz;
    if (game == null) return;
    setState(() {
      _gameLoaded = true;
      _timeLeft = game.timerSecondsPerQuestion;
      _selectedIndex = null;
      _answered = false;
      _feedbackText = null;
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
    final game = context.read<GamesProvider>().grammarQuiz!;
    final q = game.questions[_questionIndex];
    _recordTopic(game.topic, false);
    setState(() {
      _answered = true;
      _feedbackText =
          'Time\'s up! ${q.explanation.isNotEmpty ? q.explanation : ''}';
    });
    Future.delayed(const Duration(seconds: 2), _nextQuestion);
  }

  void _selectAnswer(int index) {
    if (_answered) return;
    _timer?.cancel();
    final game = context.read<GamesProvider>().grammarQuiz!;
    final q = game.questions[_questionIndex];
    final correct = index == q.correctIndex;
    if (correct) _correctCount++;
    _recordTopic(game.topic, correct);
    final masteryMsg = _buildMasteryMessage(game.topic);
    setState(() {
      _selectedIndex = index;
      _answered = true;
      _feedbackText = correct
          ? q.grammarTip.isNotEmpty
                ? q.grammarTip
                : 'Correct!'
          : '${q.explanation.isNotEmpty ? q.explanation : 'Incorrect.'}${masteryMsg.isNotEmpty ? '\n$masteryMsg' : ''}';
    });
    Future.delayed(const Duration(seconds: 2), _nextQuestion);
  }

  void _recordTopic(String topic, bool correct) {
    _topicTotal[topic] = (_topicTotal[topic] ?? 0) + 1;
    if (correct) _topicCorrect[topic] = (_topicCorrect[topic] ?? 0) + 1;
  }

  String _buildMasteryMessage(String topic) {
    final total = _topicTotal[topic] ?? 0;
    final correct = _topicCorrect[topic] ?? 0;
    if (total < 3) return '';
    final pct = correct / total * 100;
    if (pct >= 80) return 'Great mastery of ${_formatTopic(topic)}!';
    if (pct >= 50) return 'Keep practicing ${_formatTopic(topic)}.';
    return 'Review ${_formatTopic(topic)} concepts.';
  }

  String _formatTopic(String t) => t
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      })
      .join(' ');

  void _nextQuestion() {
    final game = context.read<GamesProvider>().grammarQuiz;
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
    final game = provider.grammarQuiz!;
    // Celebrate if accuracy ≥ 60% (skill: gamification-confetti-win)
    if (game.questions.isNotEmpty &&
        _correctCount / game.questions.length >= 0.6) {
      _confettiController.play();
      await Future.delayed(const Duration(milliseconds: 1200));
    }
    if (!mounted) return;
    final xpResult = await provider.completeGame(
      gameType: GameType.grammarQuiz,
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
            gameType: GameType.grammarQuiz,
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
            body: Center(child: LottieLoadingWidget.medium()),
          );
        }
        final game = provider.grammarQuiz!;
        final q = game.questions[_questionIndex];

        return Scaffold(
          backgroundColor: AppColors.backgroundLight,
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
            title: Text(
              'Question ${_questionIndex + 1}/${game.questions.length}',
              style: const TextStyle(color: AppColors.textDark),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: _TimerWidget(
                    timeLeft: _timeLeft,
                    total: game.timerSecondsPerQuestion,
                  ),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  LinearProgressIndicator(
                    value: _questionIndex / game.questions.length,
                    backgroundColor: AppColors.grey200,
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Topic chip
                          Chip(
                            label: Text(
                              _formatTopic(game.topic),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: AppColors.primary.withValues(
                              alpha: 0.1,
                            ),
                            side: const BorderSide(color: AppColors.primary),
                          ),
                          const SizedBox(height: 12),
                          // Timer bar
                          LinearProgressIndicator(
                            value: _timeLeft / game.timerSecondsPerQuestion,
                            backgroundColor: AppColors.grey200,
                            color: _timeLeft > 4
                                ? AppColors.primary
                                : AppColors.errorBright,
                            minHeight: 6,
                          ),
                          const SizedBox(height: 16),
                          // Question
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Text(
                              q.question,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Answer cards
                          ...List.generate(q.options.length, (i) {
                            Color bg = Colors.white;
                            Color border = AppColors.grey300;
                            Color text = AppColors.textDark;
                            IconData? icon;
                            if (_answered) {
                              if (i == q.correctIndex) {
                                bg = AppColors.greenSuccess.withValues(
                                  alpha: 0.1,
                                );
                                border = AppColors.greenSuccess;
                                text = AppColors.greenSuccess;
                                icon = Icons.check_circle_outline;
                              } else if (i == _selectedIndex) {
                                bg = Colors.red.withValues(alpha: 0.08);
                                border = AppColors.errorBright;
                                text = AppColors.errorBright;
                                icon = Icons.cancel_outlined;
                              }
                            } else if (_selectedIndex == i) {
                              bg = AppColors.primary.withValues(alpha: 0.1);
                              border = AppColors.primary;
                              text = AppColors.primary;
                            }
                            return GestureDetector(
                              onTap: () => _selectAnswer(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: border, width: 1.5),
                                ),
                                child: Row(
                                  children: [
                                    if (icon != null) ...[
                                      Icon(icon, color: border, size: 18),
                                      const SizedBox(width: 8),
                                    ],
                                    Expanded(
                                      child: Text(
                                        q.options[i],
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: text,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          // Feedback
                          if (_feedbackText != null) ...[
                            const SizedBox(height: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color:
                                    _answered &&
                                        _selectedIndex == q.correctIndex
                                    ? AppColors.greenSuccess.withValues(
                                        alpha: 0.08,
                                      )
                                    : Colors.red.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      _answered &&
                                          _selectedIndex == q.correctIndex
                                      ? AppColors.greenSuccess
                                      : AppColors.errorBright,
                                ),
                              ),
                              child: Text(
                                _feedbackText!,
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
                    AppColors.greenSuccessBright,
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

class _TimerWidget extends StatelessWidget {
  final int timeLeft;
  final int total;
  const _TimerWidget({required this.timeLeft, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? timeLeft / total : 0.0;
    final color = ratio > 0.5
        ? AppColors.greenSuccess
        : ratio > 0.25
        ? AppColors.orange
        : AppColors.errorBright;
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
