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

const _fillBlankPowerUps = [
  ShopItemEntity.effectTimeFreeze,
  ShopItemEntity.effectExtraTime,
  ShopItemEntity.effectSkipToken,
  ShopItemEntity.effectRevealHint,
  ShopItemEntity.effectLuckyClover,
  ShopItemEntity.effectScoreMultiplier,
];

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
  bool _isFinishing = false;
  String? _feedbackTip;
  final Map<String, String> _submittedAnswers = {};
  final Set<int> _eliminatedIndices = {};
  bool _luckyCloverActive = false;
  int _scoreMultiplier = 1;
  final _random = Random();

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
    final game = context.read<GamesProvider>().fillBlank;
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
    final game = context.read<GamesProvider>().fillBlank!;
    final q = game.questions[_questionIndex];
    _submittedAnswers[q.id] = '';
    setState(() {
      _answered = true;
      _feedbackTip = q.explanation.isNotEmpty
          ? q.explanation
          : 'fillBlank.timeoutFeedback'.tr();
    });
    Future.delayed(const Duration(seconds: 2), _nextQuestion);
  }

  void _selectAnswer(int index) {
    if (_answered || _eliminatedIndices.contains(index)) return;
    _timer?.cancel();
    final game = context.read<GamesProvider>().fillBlank!;
    final q = game.questions[_questionIndex];
    var correct = q.options[index] == q.correctAnswer;
    if (!correct && _luckyCloverActive && _random.nextDouble() < 0.3) {
      correct = true;
      _luckyCloverActive = false;
    }
    _submittedAnswers[q.id] = q.options[index];
    if (correct) _correctCount++;
    setState(() {
      _selectedIndex = index;
      _answered = true;
      _feedbackTip = correct
          ? (q.grammarTip.isNotEmpty
                ? q.grammarTip
                : 'fillBlank.correctFeedback'.tr())
          : (q.explanation.isNotEmpty
                ? q.explanation
                : 'fillBlank.incorrectFeedback'.tr());
    });
    Future.delayed(const Duration(seconds: 2), _nextQuestion);
  }

  void _nextQuestion() {
    if (!mounted || _isFinishing) return;
    final game = context.read<GamesProvider>().fillBlank;
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
        title: const Text('Thoát game?'),
        content: const Text('XP sẽ được tính dựa trên số câu đã hoàn thành.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tiếp tục chơi'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thoát'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isFinishing) return;
    _isFinishing = true;
    _timer?.cancel();
    final provider = context.read<GamesProvider>();
    final game = provider.fillBlank;
    if (game != null) {
      await provider.completeGame(
        gameType: GameType.fillBlank,
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
            gameType: GameType.fillBlank,
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
        final game = provider.fillBlank;
        if (provider.error != null) {
          return GameLoadState(
            message: 'games.loadFailed'.tr(),
            onRetry: () async {
              await provider.loadFillBlank();
              if (mounted) _startQuestion();
            },
          );
        }
        if (game == null || game.questions.isEmpty) {
          return GameLoadState(
            message: 'games.emptyGame'.tr(),
            onRetry: () async {
              await provider.loadFillBlank();
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
              'fillBlank.questionProgress'.tr(
                namedArgs: {
                  'current': '${_questionIndex + 1}',
                  'total': '${game.questions.length}',
                },
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  // Progress bar
                  LinearProgressIndicator(
                    value: (_questionIndex) / game.questions.length,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    color: AppColors.primary,
                    minHeight: 4,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: GamePowerUpTray(
                      availableTypes: _fillBlankPowerUps,
                      enabled: !_answered,
                      onUse: _onPowerUpUsed,
                    ),
                  ),
                  if (_luckyCloverActive)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: ActivePowerUpBadge(
                        itemType: ShopItemEntity.effectLuckyClover,
                        label: 'Lucky Clover Active',
                      ),
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
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _timeLeft / game.timerSecondsPerQuestion,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            color: _timeLeft > 5
                                ? AppColors.primary
                                : AppColors.errorBright,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'fillBlank.timerFormat'.tr(
                            namedArgs: {'seconds': '$_timeLeft'},
                          ),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _timeLeft > 5
                                ? Theme.of(context).colorScheme.onSurfaceVariant
                                : AppColors.errorBright,
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
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.shadow.withValues(alpha: 0.06),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Text(
                              q.sentence,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
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
                              final eliminated = _eliminatedIndices.contains(
                                i,
                              );
                              Color bg = Theme.of(context).colorScheme.surface;
                              Color border = Theme.of(
                                context,
                              ).colorScheme.outlineVariant;
                              Color text = Theme.of(
                                context,
                              ).colorScheme.onSurface;
                              if (_answered) {
                                if (q.options[i] == q.correctAnswer) {
                                  bg = AppColors.greenSuccess.withValues(
                                    alpha: 0.1,
                                  );
                                  border = AppColors.greenSuccess;
                                  text = AppColors.greenSuccess;
                                } else if (i == _selectedIndex) {
                                  bg = Colors.red.withValues(alpha: 0.1);
                                  border = AppColors.errorBright;
                                  text = AppColors.errorBright;
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
                                onTap: eliminated
                                    ? null
                                    : () => _selectAnswer(i),
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
                                    ? AppColors.greenSuccess.withValues(
                                        alpha: 0.1,
                                      )
                                    : Colors.red.withValues(alpha: 0.1),
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
                                _feedbackTip!,
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
