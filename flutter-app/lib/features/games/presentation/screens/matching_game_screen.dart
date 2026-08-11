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

const _matchingPowerUps = [
  ShopItemEntity.effectTimeFreeze,
  ShopItemEntity.effectExtraTime,
  ShopItemEntity.effectPairSwap,
  ShopItemEntity.effectLuckyClover,
  ShopItemEntity.effectScoreMultiplier,
];

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
  bool _isFinishing = false;
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

    var matched = matchText == correctMatch;
    if (!matched && _luckyCloverActive && _random.nextDouble() < 0.3) {
      matched = true;
      _luckyCloverActive = false;
    }

    if (matched) {
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

  void _onPowerUpUsed(String itemType, Map<String, dynamic> effects) {
    final game = context.read<GamesProvider>().matching;
    if (game == null) return;
    switch (itemType) {
      case ShopItemEntity.effectTimeFreeze:
      case ShopItemEntity.effectExtraTime:
        final seconds = (effects['seconds'] as num?)?.toInt() ?? 10;
        setState(
          () => _timeLeft = (_timeLeft + seconds).clamp(0, game.timerSeconds),
        );
        break;
      case ShopItemEntity.effectPairSwap:
        final remaining = game.pairs
            .where((p) => !_matchedIds.contains(p.wordId))
            .toList();
        if (remaining.isEmpty) return;
        final pair = remaining[_random.nextInt(remaining.length)];
        _correctCount++;
        setState(() {
          _matchedIds.add(pair.wordId);
          _matchState[pair.wordId] = _PairState.correct;
          if (_selectedWord == pair.wordId) {
            _selectedWord = null;
            _selectedMatch = null;
          }
        });
        if (_matchedIds.length == game.pairs.length) {
          _confettiController.play();
          _timer?.cancel();
          Future.delayed(const Duration(milliseconds: 800), _finishGame);
        }
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

  Future<void> _abandonGame() async {
    if (_isFinishing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thoát game?'),
        content: const Text('XP sẽ được tính dựa trên số cặp đã ghép đúng.'),
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
    final game = provider.matching;
    if (game != null) {
      await provider.completeGame(
        gameType: GameType.matching,
        score: _correctCount,
        totalQuestions: game.pairs.length,
        correctAnswers: _correctCount,
        answers: [
          for (final pair in game.pairs)
            {'id': pair.wordId, 'answer': _matchedIds.contains(pair.wordId) ? pair.matchText : ''},
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
    final game = provider.matching!;
    final total = game.pairs.length;

    final elapsed = game.timerSeconds - _timeLeft;
    final xpResult = await provider.completeGame(
      gameType: GameType.matching,
      score: _correctCount * _scoreMultiplier,
      totalQuestions: total,
      correctAnswers: _correctCount,
      answers: [
        for (final pair in game.pairs)
          {
            'id': pair.wordId,
            'answer': _matchedIds.contains(pair.wordId) ? pair.matchText : '',
          },
      ],
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: GameResult(
            gameType: GameType.matching,
            cefrLevel: provider.selectedLevel,
            score: _correctCount * _scoreMultiplier,
            totalQuestions: total,
            correctAnswers: _correctCount,
            xpEarned: xpResult?.xpAwarded ?? 0,
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
        final game = provider.matching;
        if (provider.error != null) {
          return GameLoadState(
            message: 'games.loadFailed'.tr(),
            onRetry: () async {
              await provider.loadMatchingGame();
              if (mounted) _initGame();
            },
          );
        }
        if (game == null || game.pairs.isEmpty) {
          return GameLoadState(
            message: 'games.emptyGame'.tr(),
            onRetry: () async {
              await provider.loadMatchingGame();
              if (mounted) _initGame();
            },
          );
        }
        if (!_gameLoaded) {
          return const Scaffold(
            body: Center(child: LottieLoadingWidget.medium()),
          );
        }
        final remaining = game.pairs
            .where((p) => !_matchedIds.contains(p.wordId))
            .toList();

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
            title: Text(
              'matchingGame.title'.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: GamePowerUpTray(
                      availableTypes: _matchingPowerUps,
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
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'matchingGame.matchedProgress'.tr(
                        namedArgs: {
                          'matched': '${_matchedIds.length}',
                          'total': '${game.pairs.length}',
                        },
                      ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                              label: 'matchingGame.wordsColumnLabel'.tr(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Matches column
                          Expanded(
                            child: _ColumnList(
                              items: game.definitionsColumn
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
                              label: game.variant == 'definition'
                                  ? 'matchingGame.definitionsLabel'.tr()
                                  : 'matchingGame.matchesLabel'.tr(),
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              Color bg = Theme.of(context).colorScheme.surface;
              Color border = Theme.of(context).colorScheme.outlineVariant;
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
                border = AppColors.errorBright;
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
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface,
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
