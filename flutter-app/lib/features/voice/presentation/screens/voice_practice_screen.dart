import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/voice_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/record_button.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/pronunciation_score_card.dart';

/// Voice Practice Screen
/// Allows users to practice pronunciation by:
/// 1. Listening to the target phrase (TTS)
/// 2. Recording their pronunciation (STT)
/// 3. Getting pronunciation assessment
class VoicePracticeScreen extends StatefulWidget {
  final String? initialPhrase;
  final String? language;

  const VoicePracticeScreen({
    super.key,
    this.initialPhrase,
    this.language = 'en',
  });

  @override
  State<VoicePracticeScreen> createState() => _VoicePracticeScreenState();
}

class _VoicePracticeScreenState extends State<VoicePracticeScreen> {
  final TextEditingController _phraseController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Timer? _recordingTimer;
  StreamSubscription<PlayerState>? _playerStateSub;
  Duration _recordingDuration = Duration.zero;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isProcessing = false;
  bool _hasRecorderPermission = false;

  // Sample phrases for practice
  final List<String> _samplePhrases = [
    "Hello, how are you today?",
    "Nice to meet you!",
    "What is your name?",
    "I love learning languages.",
    "The weather is beautiful today.",
    "Can you help me please?",
    "Thank you very much!",
    "Good morning, everyone!",
  ];

  @override
  void initState() {
    super.initState();
    _phraseController.text = widget.initialPhrase ?? _samplePhrases.first;
    _checkPermission();

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() => _isPlaying = false);
      }
    });
  }

  Future<void> _checkPermission() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!mounted) return;
      setState(() => _hasRecorderPermission = hasPermission);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasRecorderPermission = false);
    }
  }

  @override
  void dispose() {
    _phraseController.dispose();
    _playerStateSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (!_hasRecorderPermission) {
      await _checkPermission();
      if (!_hasRecorderPermission) {
        _showError('voice.microphonePermissionDenied'.tr());
        return;
      }
    }

    try {
      String? recordingPath;
      if (!kIsWeb) {
        final directory = await getTemporaryDirectory();
        recordingPath =
            '${directory.path}/recording_${DateTime.now().millisecondsSinceEpoch}.wav';
      }

      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: kIsWeb
            ? 'recording_${DateTime.now().millisecondsSinceEpoch}.wav'
            : recordingPath!,
      );

      if (!mounted) return;

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      context.read<VoiceProvider>().startRecording();

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordingDuration += const Duration(seconds: 1));
        context.read<VoiceProvider>().updateRecordingDuration(
          _recordingDuration,
        );
      });
    } catch (e) {
      _showError('voice.failedToStartRecording'.tr(namedArgs: {'error': '$e'}));
    }
  }

  Future<void> _stopRecording() async {
    _recordingTimer?.cancel();

    try {
      final path = await _recorder.stop();

      if (!mounted) return;

      setState(() => _isRecording = false);

      if (path != null) {
        final audioData = await _readRecordedAudio(path);
        if (audioData != null && audioData.isNotEmpty) {
          await _assessPronunciation(audioData, 'recording.wav');
        } else {
          _showError('voice.recordedAudioUnreadable'.tr());
        }
      } else {
        _showError('voice.noRecordedAudioReturned'.tr());
      }
    } catch (e) {
      _showError('voice.failedToStopRecording'.tr(namedArgs: {'error': '$e'}));
    }
  }

  Future<void> _assessPronunciation(
    Uint8List audioData,
    String filename,
  ) async {
    setState(() => _isProcessing = true);

    try {
      final provider = context.read<VoiceProvider>();
      await provider.assessPronunciation(
        audioData: audioData,
        filename: filename,
        targetText: _phraseController.text.trim(),
        language: widget.language,
      );
    } catch (e) {
      if (mounted) _showError('voice.assessmentFailed'.tr());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _playExample() async {
    if (_phraseController.text.trim().isEmpty) {
      _showError('voice.enterPhraseFirst'.tr());
      return;
    }

    setState(() => _isProcessing = true);

    final provider = context.read<VoiceProvider>();
    final result = await provider.synthesizeAndPlay(
      text: _phraseController.text.trim(),
    );

    if (result != null && result.audioData.isNotEmpty) {
      try {
        if (kIsWeb) {
          final audioUri = Uri.dataFromBytes(
            result.audioData,
            mimeType: 'audio/wav',
          ).toString();
          await _player.setUrl(audioUri);
        } else {
          final directory = await getTemporaryDirectory();
          final file = File('${directory.path}/tts_audio.wav');
          await file.writeAsBytes(result.audioData);
          await _player.setFilePath(file.path);
        }
        await _player.play();

        setState(() {
          _isPlaying = true;
          _isProcessing = false;
        });
      } catch (e) {
        setState(() => _isProcessing = false);
        _showError('voice.failedToPlayAudio'.tr(namedArgs: {'error': '$e'}));
      }
    } else {
      setState(() => _isProcessing = false);
    }
  }

  void _stopPlaying() {
    _player.stop();
    setState(() => _isPlaying = false);
  }

  void _selectRandomPhrase() {
    final random = (_samplePhrases.toList()..shuffle()).first;
    _phraseController.text = random;
    context.read<VoiceProvider>().clearResults();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.errorBright),
    );
  }

  Future<Uint8List?> _readRecordedAudio(String path) async {
    if (kIsWeb) {
      final uri = Uri.tryParse(path);
      if (uri == null) return null;
      final response = await http.get(uri);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    }

    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('voice.practiceTitle'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: _selectRandomPhrase,
            tooltip: 'voice.randomPhrase'.tr(),
          ),
        ],
      ),
      body: Consumer<VoiceProvider>(
        builder: (context, voiceProvider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Instructions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'voice.instructions'.tr(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Phrase input
                TextField(
                  controller: _phraseController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'voice.phraseToPractice'.tr(),
                    hintText: 'voice.enterPhraseHint'.tr(),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _phraseController.clear();
                        voiceProvider.clearResults();
                      },
                    ),
                  ),
                  onChanged: (_) => voiceProvider.clearResults(),
                ),
                const SizedBox(height: 24),

                // Listen to example button
                ElevatedButton.icon(
                  onPressed: _isPlaying || _isRecording
                      ? null
                      : (_isPlaying ? _stopPlaying : _playExample),
                  icon: Icon(_isPlaying ? Icons.stop : Icons.volume_up),
                  label: Text(
                    _isPlaying
                        ? 'voice.stop'.tr()
                        : 'voice.listenToExample'.tr(),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // Recording section
                if (!_hasRecorderPermission) ...[
                  ElevatedButton.icon(
                    onPressed: _checkPermission,
                    icon: const Icon(Icons.mic_off),
                    label: Text('voice.grantMicrophonePermission'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.orange,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ] else ...[
                  Text(
                    'voice.yourTurn'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_isProcessing) ...[
                    const LottieAnimationWidget.pulse(width: 88, height: 88),
                    const SizedBox(height: 4),
                    Text(
                      'voice.analyzingPronunciation'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textGrey,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  RecordButton(
                    isRecording: _isRecording,
                    isProcessing: _isProcessing,
                    recordingDuration: _recordingDuration,
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                  ),
                ],
                const SizedBox(height: 32),

                // Error message
                if (voiceProvider.hasError &&
                    voiceProvider.errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: AppColors.errorBright),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            voiceProvider.errorMessage!,
                            style: TextStyle(color: Colors.red.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Transcription result
                if (voiceProvider.lastTranscription != null &&
                    voiceProvider.lastPronunciationScore == null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.grey300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'voice.youSaid'.tr(),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: AppColors.textGrey),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          voiceProvider.lastTranscription!.text,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ],

                // Pronunciation score
                if (voiceProvider.lastPronunciationScore != null) ...[
                  if (voiceProvider.lastPronunciationScore!.overallScore >=
                      80) ...[
                    const LottieAnimationWidget.success(
                      width: 100,
                      height: 100,
                      repeat: false,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'voice.excellentPronunciation'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.greenSuccessBright,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  PronunciationScoreCard(
                    score: voiceProvider.lastPronunciationScore!,
                    onTryAgain: () {
                      voiceProvider.clearResults();
                    },
                    onListenExample: _playExample,
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }
}
