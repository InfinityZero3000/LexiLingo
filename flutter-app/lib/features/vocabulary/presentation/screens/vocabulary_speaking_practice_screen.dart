import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/pronunciation_evaluation_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/session_complete_screen.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/tts_speed_selector.dart';
import 'package:easy_localization/easy_localization.dart';

class VocabularySpeakingPracticeScreen extends StatefulWidget {
  const VocabularySpeakingPracticeScreen({super.key});

  @override
  State<VocabularySpeakingPracticeScreen> createState() =>
      _VocabularySpeakingPracticeScreenState();
}

class _VocabularySpeakingPracticeScreenState
    extends State<VocabularySpeakingPracticeScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Timer? _recordingTimer;
  StreamSubscription<PlayerState>? _playerStateSub;
  Duration _recordingDuration = Duration.zero;
  Uint8List? _recordedAudio;
  PronunciationEvaluationEntity? _evaluation;
  bool _isRecording = false;
  bool _isEvaluating = false;
  bool _isPlayingRecording = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<FlashcardProvider>();
      if (!provider.hasSession) {
        provider.startReviewSession();
      }
    });

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        setState(() => _isPlayingRecording = false);
      }
    });
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _playerStateSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showError('Microphone permission is required.');
      return;
    }

    try {
      String? recordingPath;
      if (!kIsWeb) {
        final directory = await getTemporaryDirectory();
        recordingPath =
            '${directory.path}/vocab_speaking_${DateTime.now().millisecondsSinceEpoch}.wav';
      }

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: kIsWeb
            ? 'vocab_speaking_${DateTime.now().millisecondsSinceEpoch}.wav'
            : recordingPath!,
      );

      if (!mounted) return;
      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
        _evaluation = null;
        _recordedAudio = null;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordingDuration += const Duration(seconds: 1));
      });
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();

    try {
      final path = await _recorder.stop();
      if (!mounted) return;

      setState(() => _isRecording = false);

      if (path == null) {
        _showError('No recorded audio was returned.');
        return;
      }

      final audioData = await _readRecordedAudio(path);
      if (audioData == null || audioData.isEmpty) {
        _showError('Recorded audio is empty.');
        return;
      }

      setState(() => _recordedAudio = audioData);
      await _evaluateCurrentRecording(audioData);
    } catch (e) {
      _showError('Failed to stop recording: $e');
    }
  }

  Future<Uint8List?> _readRecordedAudio(String path) async {
    if (kIsWeb) {
      final uri = Uri.tryParse(path);
      if (uri == null) return null;
      final response = await http.get(uri);
      return response.statusCode == 200 ? response.bodyBytes : null;
    }

    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> _evaluateCurrentRecording(Uint8List audioData) async {
    final provider = context.read<FlashcardProvider>();
    final currentCard = provider.currentSession?.currentCard;
    if (currentCard == null) return;

    setState(() => _isEvaluating = true);

    final result = await provider.vocabularyRepository.evaluatePronunciation(
      vocabularyId: currentCard.vocabularyItem.id,
      audioData: audioData,
      filename: 'recording.wav',
    );

    if (!mounted) return;
    result.fold(
      (failure) {
        setState(() => _isEvaluating = false);
        _showError(failure.message);
      },
      (evaluation) {
        setState(() {
          _evaluation = evaluation;
          _isEvaluating = false;
        });
      },
    );
  }

  Future<void> _playRecording() async {
    final audio = _recordedAudio;
    if (audio == null || audio.isEmpty) return;

    try {
      if (_isPlayingRecording) {
        await _player.stop();
        setState(() => _isPlayingRecording = false);
        return;
      }

      if (kIsWeb) {
        final audioUri = Uri.dataFromBytes(
          audio,
          mimeType: 'audio/wav',
        ).toString();
        await _player.setUrl(audioUri);
      } else {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/vocab_recording_playback.wav');
        await file.writeAsBytes(audio);
        await _player.setFilePath(file.path);
      }

      await _player.play();
      if (mounted) setState(() => _isPlayingRecording = true);
    } catch (e) {
      _showError('Failed to play recording: $e');
    }
  }

  Future<void> _submitResult() async {
    final evaluation = _evaluation;
    if (evaluation == null) return;

    final provider = context.read<FlashcardProvider>();
    await provider.submitReview(_qualityFromEvaluation(evaluation));

    if (!mounted) return;
    if (provider.currentSession?.isCompleted ?? false) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              SessionCompleteScreen(session: provider.currentSession!),
        ),
      );
      return;
    }

    setState(() {
      _evaluation = null;
      _recordedAudio = null;
      _recordingDuration = Duration.zero;
      _isPlayingRecording = false;
    });
  }

  ReviewQuality _qualityFromEvaluation(
    PronunciationEvaluationEntity evaluation,
  ) {
    if (evaluation.score >= 80) return ReviewQuality.perfect;
    if (evaluation.score >= 60) return ReviewQuality.good;
    return ReviewQuality.incorrect;
  }

  void _tryAgain() {
    setState(() {
      _evaluation = null;
      _recordedAudio = null;
      _recordingDuration = Duration.zero;
      _isPlayingRecording = false;
    });
  }

  void _showMeaning(ReviewCardEntity card) {
    final vocabulary = card.vocabularyItem;
    final translation = vocabulary.vietnameseTranslation;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vocabulary.word,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(vocabulary.definition),
            if (translation != null && translation.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                translation,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.errorBright),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAF7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'lesson.exercise.speakingTitle'.tr(),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'common.minimize'.tr(),
            icon: const Icon(Icons.remove),
            onPressed: () {},
          ),
          IconButton(
            tooltip: 'common.maximize'.tr(),
            icon: const Icon(Icons.crop_square),
            onPressed: () {},
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Consumer<FlashcardProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.hasSession) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null) {
            return _buildMessageState(
              icon: Icons.error_outline,
              message: provider.errorMessage!,
              actionLabel: 'voice.tryAgain'.tr(),
              onAction: () {
                provider.clearError();
                provider.startReviewSession();
              },
            );
          }

          final session = provider.currentSession;
          final card = session?.currentCard;
          if (session == null || card == null) {
            return _buildMessageState(
              icon: Icons.check_circle_outline,
              message: 'vocabulary.noSpeakingDue'.tr(),
              actionLabel: 'common.close'.tr(),
              onAction: () => Navigator.of(context).pop(),
            );
          }

          return SafeArea(
            child: Column(
              children: [
                _buildTopBar(session, card),
                Expanded(child: _buildPracticeBody(card)),
                _buildResultPanel(provider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(ReviewSessionEntity session, ReviewCardEntity card) {
    final current = session.reviewedCards + 1;
    final total = session.totalCards;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(
        children: [
          SpeakButton(
            text: card.vocabularyItem.word,
            mini: true,
            size: 42,
            color: const Color(0xFF228B52),
          ),
          const SizedBox(width: 8),
          const TtsSpeedButton(),
          const SizedBox(width: 18),
          Text(
            'vocabulary.itemNumber'.tr(namedArgs: {'current': '$current'}),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 10,
                value: total == 0 ? 0 : current / total,
                backgroundColor: const Color(0xFFDDE8DE),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF2EAE5B)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('vocabulary.totalCount'.tr(namedArgs: {'total': '$total'})),
        ],
      ),
    );
  }

  Widget _buildPracticeBody(ReviewCardEntity card) {
    final vocabulary = card.vocabularyItem;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 18),
      child: Column(
        children: [
          Text(
            vocabulary.word,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF168348),
              fontSize: 48,
              fontWeight: FontWeight.w900,
              height: 1.05,
            ),
          ),
          if (vocabulary.pronunciation != null) ...[
            const SizedBox(height: 12),
            Text(
              '/${vocabulary.pronunciation}/',
              style: const TextStyle(
                color: Color(0xFF6A7A70),
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _showMeaning(card),
            icon: const Icon(Icons.translate),
            label: Text('vocabulary.meaning'.tr()),
          ),
          const SizedBox(height: 34),
          _buildRecordControl(),
        ],
      ),
    );
  }

  Widget _buildRecordControl() {
    return Column(
      children: [
        GestureDetector(
          onTap: _isEvaluating ? null : _toggleRecording,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: _isRecording ? const Color(0xFFFFE8E8) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: _isRecording
                    ? AppColors.errorBright
                    : const Color(0xFF2EAE5B),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2EAE5B).withValues(alpha: 0.16),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Icon(
              _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
              color: _isRecording
                  ? AppColors.errorBright
                  : const Color(0xFF168348),
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _isRecording ? _formatDuration(_recordingDuration) : 'Tap to record',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 34,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(13, (index) {
              final active = _isRecording || _isEvaluating;
              final height = active ? 8.0 + ((index % 5) * 5.0) : 8.0;
              return AnimatedContainer(
                duration: Duration(milliseconds: 160 + index * 12),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 5,
                height: height,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFF2EAE5B)
                      : const Color(0xFFC9D8CE),
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildResultPanel(FlashcardProvider provider) {
    final evaluation = _evaluation;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE1E9E3))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isEvaluating)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: CircularProgressIndicator(),
            )
          else if (evaluation != null)
            _buildEvaluation(evaluation, provider)
          else
            const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildEvaluation(
    PronunciationEvaluationEntity evaluation,
    FlashcardProvider provider,
  ) {
    return Column(
      children: [
        Text(
          evaluation.feedbackLabel,
          style: const TextStyle(
            color: Color(0xFF168348),
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _recordedAudio == null ? null : _playRecording,
          icon: Icon(_isPlayingRecording ? Icons.stop : Icons.play_arrow),
          label: Text('voice.yourPronunciation'.tr()),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            return Icon(
              index < evaluation.stars ? Icons.star : Icons.star_border,
              color: const Color(0xFFFFC43D),
              size: 34,
            );
          }),
        ),
        if (evaluation.transcription != null &&
            evaluation.transcription!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            evaluation.transcription!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF617067)),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: provider.isLoading ? null : _tryAgain,
                child: Text('voice.tryAgain'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: provider.isLoading ? null : _submitResult,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF168348),
                  foregroundColor: Colors.white,
                ),
                child: provider.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('common.submit'.tr()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: const Color(0xFF168348)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
