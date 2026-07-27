import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/games/data/services/game_pronunciation_service.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_load_state.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_powerup_tray.dart';

const _spellingBeePowerUps = [
  ShopItemEntity.effectMistakeShield,
  ShopItemEntity.effectTranslateHint,
  ShopItemEntity.effectSkipToken,
  ShopItemEntity.effectScoreMultiplier,
];

/// Spelling Bee game screen.
///
/// Player listens to TTS audio and types the word they heard.
/// Tracks replays and gives IPA + definition after each answer.
class SpellingBeeScreen extends StatefulWidget {
  const SpellingBeeScreen({super.key});

  @override
  State<SpellingBeeScreen> createState() => _SpellingBeeScreenState();
}

class _SpellingBeeScreenState extends State<SpellingBeeScreen> {
  final TextEditingController _inputController = TextEditingController();
  late GamePronunciationService _pronunciationService;

  int _wordIndex = 0;
  int _playsLeft = 3;
  int _correctCount = 0;
  bool _gameLoaded = false;
  bool _answered = false;
  bool _isCorrect = false;
  bool _isFinishing = false;
  String? _audioErrorMessage;
  String? _translationReveal;
  int _scoreMultiplier = 1;
  final Map<String, String> _submittedAnswers = {};

  @override
  void initState() {
    super.initState();
    _pronunciationService = sl<GamePronunciationService>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamesProvider>().loadSpellingBee().then((_) {
        if (mounted) _initWord();
      });
    });
  }

  @override
  void dispose() {
    _pronunciationService.dispose();
    _inputController.dispose();
    super.dispose();
  }

  void _initWord() {
    final game = context.read<GamesProvider>().spellingBee;
    if (game == null) return;
    setState(() {
      _gameLoaded = true;
      _playsLeft = game.words[_wordIndex].maxReplays;
      _answered = false;
      _isCorrect = false;
      _audioErrorMessage = null;
      _translationReveal = null;
      _inputController.clear();
    });
  }

  void _onPowerUpUsed(String itemType, Map<String, dynamic> effects) {
    if (_answered) return;
    final game = context.read<GamesProvider>().spellingBee;
    if (game == null) return;
    final word = game.words[_wordIndex];
    switch (itemType) {
      case ShopItemEntity.effectMistakeShield:
        setState(() => _playsLeft += 1);
        break;
      case ShopItemEntity.effectTranslateHint:
        setState(() => _translationReveal = word.vietnameseTranslation);
        break;
      case ShopItemEntity.effectSkipToken:
        _submittedAnswers[word.wordId] = '';
        setState(() => _answered = true);
        Future.delayed(const Duration(milliseconds: 300), _nextWord);
        break;
      case ShopItemEntity.effectScoreMultiplier:
        final multiplier = (effects['multiplier'] as num?)?.toInt() ?? 2;
        setState(() => _scoreMultiplier = multiplier);
        break;
    }
  }

  Future<void> _playAudio() async {
    if (_playsLeft <= 0 || _pronunciationService.isPlaying) return;
    final game = context.read<GamesProvider>().spellingBee;
    if (game == null) return;
    final word = game.words[_wordIndex];

    final newPlaysLeft = await _pronunciationService.play(
      text: word.word,
      playsLeft: _playsLeft,
      audioUrl: word.audioUrl,
      onPlayingChanged: () {
        if (mounted) setState(() {});
      },
    );

    if (!mounted) return;
    final error = _pronunciationService.lastError;
    setState(() {
      _playsLeft = newPlaysLeft;
      _audioErrorMessage = error?.retryable == true ? error?.message : null;
    });
  }

  void _submitAnswer() {
    if (_answered) return;
    final game = context.read<GamesProvider>().spellingBee!;
    final word = game.words[_wordIndex];
    final input = _inputController.text.trim().toLowerCase();
    final correct = word.word.toLowerCase();
    _submittedAnswers[word.wordId] = _inputController.text.trim();
    final isCorrect = input == correct;
    if (isCorrect) {
      _correctCount++;
    }
    setState(() {
      _answered = true;
      _isCorrect = isCorrect;
    });
  }

  void _nextWord() {
    if (!mounted || _isFinishing) return;
    final game = context.read<GamesProvider>().spellingBee;
    if (game == null) return;
    if (_wordIndex + 1 >= game.words.length) {
      _finishGame();
      return;
    }
    setState(() => _wordIndex++);
    _initWord();
  }

  Future<void> _abandonGame() async {
    if (_isFinishing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('spellingBee.abandonTitle'.tr()),
        content: Text('spellingBee.abandonBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('spellingBee.keepPlaying'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('spellingBee.quit'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _isFinishing) return;
    _isFinishing = true;
    final provider = context.read<GamesProvider>();
    final game = provider.spellingBee;
    if (game != null) {
      await provider.completeGame(
        gameType: GameType.spellingBee,
        score: _correctCount,
        totalQuestions: game.words.length,
        correctAnswers: _correctCount,
        answers: [
          for (final word in game.words)
            {'id': word.wordId, 'answer': _submittedAnswers[word.wordId] ?? ''},
        ],
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _finishGame() async {
    if (_isFinishing) return;
    _isFinishing = true;
    final provider = context.read<GamesProvider>();
    final game = provider.spellingBee!;
    final xpResult = await provider.completeGame(
      gameType: GameType.spellingBee,
      score: _correctCount * _scoreMultiplier,
      totalQuestions: game.words.length,
      correctAnswers: _correctCount,
      answers: [
        for (final word in game.words)
          {
            'id': word.wordId,
            'answer': _submittedAnswers[word.wordId] ?? '',
          },
      ],
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: GameResult(
            gameType: GameType.spellingBee,
            cefrLevel: provider.selectedLevel,
            score: _correctCount * _scoreMultiplier,
            totalQuestions: game.words.length,
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
          final game = provider.spellingBee;
          if (provider.error != null) {
            return GameLoadState(
              message: 'games.loadFailed'.tr(),
              onRetry: () async {
                await provider.loadSpellingBee();
                if (mounted) _initWord();
              },
            );
          }
          if (game == null || game.words.isEmpty) {
            return GameLoadState(
              message: 'games.emptyGame'.tr(),
              onRetry: () async {
                await provider.loadSpellingBee();
                if (mounted) _initWord();
              },
            );
          }
          if (!_gameLoaded) {
            return const Scaffold(
              body: Center(child: LottieLoadingWidget.medium()),
            );
          }
          final word = game.words[_wordIndex];
          final isPlaying = _pronunciationService.isPlaying;

          return Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).colorScheme.surface,
              elevation: 0,
              title: Text(
                'spellingBee.wordProgress'.tr(
                  namedArgs: {
                    'current': '${_wordIndex + 1}',
                    'total': '${game.words.length}',
                  },
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
            ),
            body: Column(
              children: [
                LinearProgressIndicator(
                  value: _wordIndex / game.words.length,
                  backgroundColor: AppColors.grey200,
                  color: AppColors.primary,
                  minHeight: 4,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: GamePowerUpTray(
                    availableTypes: _spellingBeePowerUps,
                    enabled: !_answered,
                    onUse: _onPowerUpUsed,
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const SizedBox(height: 20),
                        if (_translationReveal != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.purple.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.purple.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.translate_rounded,
                                  size: 16,
                                  color: AppColors.purple,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _translationReveal!,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // Audio error banner
                        if (_audioErrorMessage != null)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.volume_off_rounded,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'spellingBee.audioError'.tr(),
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    _pronunciationService.clearError();
                                    setState(() => _audioErrorMessage = null);
                                    _playAudio();
                                  },
                                  child: Text('spellingBee.retryAudio'.tr()),
                                ),
                              ],
                            ),
                          ),
                        // Big listen button
                        Semantics(
                          button: true,
                          label: _playsLeft > 0
                              ? 'spellingBee.listenButtonLabel'.tr()
                              : 'spellingBee.noPlaysLeft'.tr(),
                          child: GestureDetector(
                            onTap: _playsLeft > 0 && !isPlaying
                                ? _playAudio
                                : null,
                            child: AnimatedContainer(
                              duration: MediaQuery.of(context).disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 200),
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: _playsLeft > 0
                                      ? [
                                          AppColors.primary,
                                          const Color(0xFF38B2FF),
                                        ]
                                      : [AppColors.grey300, AppColors.grey200],
                                ),
                                boxShadow: _playsLeft > 0
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ]
                                    : [],
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                isPlaying
                                    ? Icons.volume_up
                                    : Icons.play_arrow_rounded,
                                color: Theme.of(context).colorScheme.surface,
                                size: 52,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'spellingBee.playsLeftLabel'.tr(
                            namedArgs: {
                              'plays': '$_playsLeft',
                              'max': '${word.maxReplays}',
                            },
                          ),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Input field
                        TextField(
                          controller: _inputController,
                          enabled: !_answered,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          decoration: InputDecoration(
                            hintText: 'spellingBee.inputHint'.tr(),
                            hintStyle: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.grey300,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.primary,
                                width: 2,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _answered ? null : _submitAnswer(),
                        ),
                        const SizedBox(height: 16),
                        if (!_answered) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitAnswer,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'spellingBee.submitButton'.tr(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Answer revealed
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: _isCorrect
                                  ? AppColors.greenSuccess.withValues(alpha: 0.1)
                                  : Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isCorrect
                                    ? AppColors.greenSuccess
                                    : AppColors.errorBright,
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _isCorrect
                                      ? 'spellingBee.correctFeedback'.tr()
                                      : 'spellingBee.answerRevealLabel'.tr(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _isCorrect
                                        ? AppColors.greenSuccess
                                        : AppColors.errorBright,
                                  ),
                                ),
                                if (!_isCorrect) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    word.word,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                  ),
                                ],
                                if (word.ipaPronunciation?.isNotEmpty ??
                                    false) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    word.ipaPronunciation!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                if (word.definition.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    word.definition,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                      height: 1.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _nextWord,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                _wordIndex + 1 < game.words.length
                                    ? 'spellingBee.nextWordButton'.tr()
                                    : 'spellingBee.seeResultsButton'.tr(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
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
          );
        },
      ),
    );
  }
}
