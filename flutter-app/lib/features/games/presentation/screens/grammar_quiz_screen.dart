import 'dart:async';
import 'dart:math';
import 'package:confetti/confetti.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_load_state.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_powerup_tray.dart';

const _grammarQuizPowerUps = [
  ShopItemEntity.effectTimeFreeze,
  ShopItemEntity.effectExtraTime,
  ShopItemEntity.effectSkipToken,
  ShopItemEntity.effectRevealHint,
  ShopItemEntity.effectLuckyClover,
  ShopItemEntity.effectScoreMultiplier,
];

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
  bool _isFinishing = false;
  String? _feedbackText;
  final Map<String, String> _submittedAnswers = {};
  final Set<int> _eliminatedIndices = {};
  bool _luckyCloverActive = false;
  int _scoreMultiplier = 1;
  final _random = Random();

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
      _eliminatedIndices.clear();
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

  void _onPowerUpUsed(String itemType, Map<String, dynamic> effects) {
    if (_answered) return;
    final game = context.read<GamesProvider>().grammarQuiz;
    if (game == null) return;
    final q = game.questions[_questionIndex];
    switch (itemType) {
      case ShopItemEntity.effectTimeFreeze:
      case ShopItemEntity.effectExtraTime:
        final seconds = (effects['seconds'] as num?)?.toInt() ?? 10;
        setState(
          () => _timeLeft = (_timeLeft + seconds).clamp(
            0,
            game.timerSecondsPerQuestion,
          ),
        );
        break;
      case ShopItemEntity.effectSkipToken:
        _timer?.cancel();
        _submittedAnswers[q.id] = '';
        setState(() => _answered = true);
        Future.delayed(const Duration(milliseconds: 300), _nextQuestion);
        break;
      case ShopItemEntity.effectRevealHint:
        final wrongIndices = List.generate(q.options.length, (i) => i)
            .where(
              (i) =>
                  q.options[i] != q.correctAnswer &&
                  !_eliminatedIndices.contains(i),
            )
            .toList();
        wrongIndices.shuffle(_random);
        setState(() {
          _eliminatedIndices.addAll(wrongIndices.take(2));
        });
        break;
      case ShopItemEntity.effectLuckyClover:
        setState(() => _luckyCloverActive = true);
        break;
      case ShopItemEntity.effectScoreMultiplier:
        final multiplier = (effects['multiplier'] as num?)?.toInt() ?? 2;
        setState(() => _scoreMultiplier = multiplier);
        break;
    }
  }

  void _handleTimeout() {
    if (_answered) return;
    final game = context.read<GamesProvider>().grammarQuiz!;
    final q = game.questions[_questionIndex];
    _submittedAnswers[q.id] = '';
    _recordTopic(q.topic, false);
    setState(() {
      _answered = true;
      _feedbackText =
          '${'grammarQuiz.timeoutFeedback'.tr()} ${q.explanation.isNotEmpty ? q.explanation : ''}';
    });
    Future.delayed(const Duration(seconds: 2), _nextQuestion);
  }

  void _selectAnswer(int index) {
    if (_answered || _eliminatedIndices.contains(index)) return;
    _timer?.cancel();
    final game = context.read<GamesProvider>().grammarQuiz!;
    final q = game.questions[_questionIndex];
    var correct = q.options[index] == q.correctAnswer;
    if (!correct && _luckyCloverActive && _random.nextDouble() < 0.3) {
      correct = true;
      _luckyCloverActive = false;
    }
    _submittedAnswers[q.id] = q.options[index];
    if (correct) _correctCount++;
    _recordTopic(q.topic, correct);
    final masteryMsg = _buildMasteryMessage(q.topic);
    setState(() {
      _selectedIndex = index;
      _answered = true;
      _feedbackText = correct
          ? q.explanation.isNotEmpty
                ? q.explanation
                : 'grammarQuiz.correctFeedback'.tr()
          : '${q.explanation.isNotEmpty ? q.explanation : 'grammarQuiz.incorrectFeedback'.tr()}${masteryMsg.isNotEmpty ? '\n$masteryMsg' : ''}';
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
    if (pct >= 80) {
      return 'grammarQuiz.greatMastery'.tr(
        namedArgs: {'topic': _formatTopic(topic)},
      );
    }
    if (pct >= 50) {
      return 'grammarQuiz.keepPracticing'.tr(
        namedArgs: {'topic': _formatTopic(topic)},
      );
    }
    return 'grammarQuiz.reviewConcepts'.tr(
      namedArgs: {'topic': _formatTopic(topic)},
    );
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
    if (!mounted || _isFinishing) return;
    final game = context.read<GamesProvider>().grammarQuiz;
    if (game == null) return;
    if (_questionIndex + 1 >= game.questions.length) {
      _finishGame();
      return;
    }
    setState(() => _questionIndex++);
    _startQuestion();
  }

  Future<void> _abandonGame() async {
    if (_isFinishing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('games.exitTitle'.tr()),
        content: Text('games.exitXpByQuestions'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('games.keepPlaying'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('games.exit'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isFinishing) return;
    _isFinishing = true;
    _timer?.cancel();
    final provider = context.read<GamesProvider>();
    final game = provider.grammarQuiz;
    if (game != null) {
      await provider.completeGame(
        gameType: GameType.grammarQuiz,
        score: _correctCount,
        totalQuestions: game.questions.length,
        correctAnswers: _correctCount,
        answers: [
          for (final q in game.questions)
            {'id': q.id, 'answer': _submittedAnswers[q.id] ?? ''},
        ],
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _finishGame() async {
    if (_isFinishing) return;
    _isFinishing = true;
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
      score: _correctCount * _scoreMultiplier,
      totalQuestions: game.questions.length,
      correctAnswers: _correctCount,
      answers: [
        for (final question in game.questions)
          {
            'id': question.id,
            'answer': _submittedAnswers[question.id] ?? '',
          },
      ],
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: GameResult(
            gameType: GameType.grammarQuiz,
            cefrLevel: provider.selectedLevel,
            score: _correctCount * _scoreMultiplier,
            totalQuestions: game.questions.length,
            correctAnswers: _correctCount,
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _abandonGame();
      },
      child: Consumer<GamesProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Scaffold(
              body: Center(child: LottieLoadingWidget.medium()),
            );
          }
          final game = provider.grammarQuiz;
          if (provider.error != null) {
            return GameLoadState(
              message: 'games.loadFailed'.tr(),
              onRetry: () async {
                await provider.loadGrammarQuiz();
              if (mounted) _startQuestion();
            },
          );
        }
        if (game == null || game.questions.isEmpty) {
          return GameLoadState(
            message: 'games.emptyGame'.tr(),
            onRetry: () async {
              await provider.loadGrammarQuiz();
              if (mounted) _startQuestion();
            },
          );
        }
        if (!_gameLoaded) {
          return const Scaffold(
            body: Center(child: LottieLoadingWidget.medium()),
          );
        }
        final q = game.questions[_questionIndex];

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
            title: Text(
              'grammarQuiz.questionProgress'.tr(
                namedArgs: {
                  'current': '${_questionIndex + 1}',
                  'total': '${game.questions.length}',
                },
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GamePowerUpTray(
                            availableTypes: _grammarQuizPowerUps,
                            enabled: !_answered,
                            onUse: _onPowerUpUsed,
                          ),
                          if (_luckyCloverActive)
                            Padding(
                              padding: EdgeInsets.only(top: 6),
                              child: ActivePowerUpBadge(
                                itemType: ShopItemEntity.effectLuckyClover,
                                label: 'games.luckyCloverActive'.tr(),
                              ),
                            ),
                          const SizedBox(height: 12),
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
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
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
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.shadow.withValues(alpha: 0.05),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Text(
                              q.question,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Answer cards
                          ...List.generate(q.options.length, (i) {
                            final eliminated = _eliminatedIndices.contains(i);
                            Color bg = Theme.of(context).colorScheme.surface;
                            Color border = Theme.of(
                              context,
                            ).colorScheme.outlineVariant;
                            Color text = Theme.of(
                              context,
                            ).colorScheme.onSurface;
                            IconData? icon;
                            if (_answered) {
                              if (q.options[i] == q.correctAnswer) {
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
                            } else if (eliminated) {
                              bg = Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest;
                              text = Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.4,
                              );
                            }
                            return GestureDetector(
                              onTap: eliminated ? null : () => _selectAnswer(i),
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
                                        _selectedIndex != null &&
                                        q.options[_selectedIndex!] ==
                                            q.correctAnswer
                                    ? AppColors.greenSuccess.withValues(
                                        alpha: 0.08,
                                      )
                                    : Colors.red.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color:
                                      _answered &&
                                          _selectedIndex != null &&
                                          q.options[_selectedIndex!] ==
                                              q.correctAnswer
                                      ? AppColors.greenSuccess
                                      : AppColors.errorBright,
                                ),
                              ),
                              child: Text(
                                _feedbackText!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
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
      ),
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
