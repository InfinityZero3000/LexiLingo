import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_result_screen.dart';

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
  late AudioPlayer _audioPlayer;

  int _wordIndex = 0;
  int _playsLeft = 3;
  int _correctCount = 0;
  int _totalXpEarned = 0;
  bool _gameLoaded = false;
  bool _answered = false;
  bool _isCorrect = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GamesProvider>().loadSpellingBee().then((_) {
        if (mounted) _initWord();
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
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
      _inputController.clear();
    });
  }

  Future<void> _playAudio() async {
    if (_playsLeft <= 0 || _isPlaying) return;
    final game = context.read<GamesProvider>().spellingBee!;
    final word = game.words[_wordIndex];
    final audioUrl = word.audioUrl;
    setState(() {
      _playsLeft--;
      _isPlaying = true;
    });
    if (audioUrl == null || audioUrl.isEmpty) {
      if (mounted) setState(() => _isPlaying = false);
      return;
    }
    try {
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();
      await _audioPlayer.playerStateStream
          .firstWhere((s) => s.processingState == ProcessingState.completed)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // Fallback: open with url_launcher if just_audio fails
      final uri = Uri.tryParse(audioUrl);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } finally {
      if (mounted) setState(() => _isPlaying = false);
    }
  }

  void _submitAnswer() {
    if (_answered) return;
    final game = context.read<GamesProvider>().spellingBee!;
    final word = game.words[_wordIndex];
    final input = _inputController.text.trim().toLowerCase();
    final correct = word.word.toLowerCase();
    final isCorrect = input == correct;
    if (isCorrect) {
      _correctCount++;
      _totalXpEarned += word.xpFull ?? word.xpValue;
    } else if (input.isNotEmpty) {
      // Partial credit: more than 50% letters correct
      final overlap = _countOverlap(input, correct);
      if (overlap > correct.length ~/ 2) {
        _totalXpEarned += word.xpPartial ?? 0;
      }
    }
    setState(() {
      _answered = true;
      _isCorrect = isCorrect;
    });
  }

  int _countOverlap(String a, String b) {
    int count = 0;
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] == b[i]) count++;
    }
    return count;
  }

  void _nextWord() {
    final game = context.read<GamesProvider>().spellingBee;
    if (game == null) return;
    if (_wordIndex + 1 >= game.words.length) {
      _finishGame();
      return;
    }
    setState(() => _wordIndex++);
    _initWord();
  }

  void _finishGame() async {
    final provider = context.read<GamesProvider>();
    final game = provider.spellingBee!;
    final xpResult = await provider.completeGame(
      gameType: GameType.spellingBee,
      score: _correctCount,
      totalQuestions: game.words.length,
      correctAnswers: _correctCount,
      baseXp: _totalXpEarned,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameResultScreen(
          result: GameResult(
            gameType: GameType.spellingBee,
            cefrLevel: provider.selectedLevel,
            score: _correctCount,
            totalQuestions: game.words.length,
            correctAnswers: _correctCount,
            xpEarned: _totalXpEarned,
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
        final game = provider.spellingBee!;
        final word = game.words[_wordIndex];

        return Scaffold(
          backgroundColor: AppColors.backgroundLight,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            title: Text(
              'Word ${_wordIndex + 1}/${game.words.length}',
              style: const TextStyle(color: AppColors.textDark),
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
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      // Big listen button
                      GestureDetector(
                        onTap: _playsLeft > 0 && !_isPlaying
                            ? _playAudio
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: _playsLeft > 0
                                  ? [AppColors.primary, const Color(0xFF38B2FF)]
                                  : [AppColors.grey300, AppColors.grey200],
                            ),
                            boxShadow: _playsLeft > 0
                                ? [
                                    BoxShadow(
                                      color: AppColors.primary.withOpacity(0.4),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : [],
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            _isPlaying
                                ? Icons.volume_up
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 52,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Plays left: $_playsLeft/${word.maxReplays}',
                        style: const TextStyle(
                          color: AppColors.textGrey,
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
                          hintText: 'Type the word...',
                          hintStyle: const TextStyle(color: AppColors.textGrey),
                          filled: true,
                          fillColor: Colors.white,
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Submit',
                              style: TextStyle(
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
                                ? AppColors.greenSuccess.withOpacity(0.1)
                                : Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isCorrect
                                  ? AppColors.greenSuccess
                                  : Colors.red,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                _isCorrect ? 'Correct!' : 'The answer was:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _isCorrect
                                      ? AppColors.greenSuccess
                                      : Colors.red,
                                ),
                              ),
                              if (!_isCorrect) ...[
                                const SizedBox(height: 4),
                                Text(
                                  word.word,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ],
                              if (word.ipaPronunciation?.isNotEmpty ??
                                  false) ...[
                                const SizedBox(height: 4),
                                Text(
                                  word.ipaPronunciation!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textGrey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                              if (word.definition.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  word.definition,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textDark,
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
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              _wordIndex + 1 < game.words.length
                                  ? 'Next Word'
                                  : 'See Results',
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
    );
  }
}
