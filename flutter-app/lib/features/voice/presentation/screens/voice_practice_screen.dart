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
  static const Duration _maxRecordingDuration = Duration(seconds: 20);

  final TextEditingController _phraseController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Timer? _recordingTimer;
  StreamSubscription<PlayerState>? _playerStateSub;
  Duration _recordingDuration = Duration.zero;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isProcessing = false;
  bool _isPreparingExample = false;
  bool _hasRecorderPermission = false;
  Uint8List? _lastRecordingAudioData;
  String _lastRecordingFilename = 'recording.wav';

  bool get _isBusy => _isProcessing || _isPreparingExample;

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
        if (!mounted) return;
        setState(() => _isPlaying = false);
        context.read<VoiceProvider>().onPlaybackComplete();
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
    if (_phraseController.text.trim().isEmpty) {
      _showError('voice.enterPhraseFirst'.tr());
      return;
    }

    if (_isBusy) return;
    if (_isPlaying) _stopPlaying();

    if (!_hasRecorderPermission) {
      await _checkPermission();
      if (!mounted) return;
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

      final provider = context.read<VoiceProvider>();
      provider.clearResults();
      provider.startRecording();

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        final duration = _recordingDuration + const Duration(seconds: 1);
        setState(() => _recordingDuration = duration);
        context.read<VoiceProvider>().updateRecordingDuration(duration);
        if (duration >= _maxRecordingDuration) {
          timer.cancel();
          unawaited(_stopRecording());
        }
      });
    } catch (e) {
      _showError('voice.failedToStartRecording'.tr(namedArgs: {'error': '$e'}));
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _isProcessing = true;
    });

    try {
      final path = await _recorder.stop();

      if (!mounted) return;

      if (path != null) {
        final audioData = await _readRecordedAudio(path);
        if (!mounted) return;
        if (audioData != null && audioData.isNotEmpty) {
          _lastRecordingAudioData = audioData;
          _lastRecordingFilename = 'recording.wav';
          await _assessPronunciation(audioData, _lastRecordingFilename);
        } else {
          setState(() => _isProcessing = false);
          context.read<VoiceProvider>().resetState();
          _showError('voice.recordedAudioUnreadable'.tr());
        }
      } else {
        setState(() => _isProcessing = false);
        context.read<VoiceProvider>().resetState();
        _showError('voice.noRecordedAudioReturned'.tr());
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecording = false;
          _isProcessing = false;
        });
        context.read<VoiceProvider>().resetState();
      }
      _showError('voice.failedToStopRecording'.tr(namedArgs: {'error': '$e'}));
    }
  }

  Future<void> _assessPronunciation(
    Uint8List audioData,
    String filename,
  ) async {
    final targetText = _phraseController.text.trim();
    if (targetText.isEmpty) {
      _showError('voice.enterPhraseFirst'.tr());
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final provider = context.read<VoiceProvider>();
      await provider.assessPronunciation(
        audioData: audioData,
        filename: filename,
        targetText: targetText,
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

    if (_isPlaying) {
      _stopPlaying();
      return;
    }

    setState(() => _isPreparingExample = true);

    final provider = context.read<VoiceProvider>();
    final result = await provider.synthesizeAndPlay(
      text: _phraseController.text.trim(),
    );
    if (!mounted) return;

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
          _isPreparingExample = false;
        });
      } catch (e) {
        if (!mounted) return;
        provider.resetState();
        setState(() => _isPreparingExample = false);
        _showError('voice.failedToPlayAudio'.tr(namedArgs: {'error': '$e'}));
      }
    } else {
      provider.resetState();
      setState(() => _isPreparingExample = false);
    }
  }

  void _stopPlaying() {
    _player.stop();
    setState(() => _isPlaying = false);
    context.read<VoiceProvider>().onPlaybackComplete();
  }

  void _selectRandomPhrase() {
    if (_isBusy || _isRecording) return;
    final random = (_samplePhrases.toList()..shuffle()).first;
    setState(() {
      _phraseController.text = random;
      _lastRecordingAudioData = null;
    });
    context.read<VoiceProvider>().clearResults();
  }

  Future<void> _retryAssessment() async {
    final audioData = _lastRecordingAudioData;
    if (audioData == null || audioData.isEmpty) {
      _showError('voice.noRecordedAudioReturned'.tr());
      return;
    }

    context.read<VoiceProvider>().resetState();
    await _assessPronunciation(audioData, _lastRecordingFilename);
  }

  void _showError(String message) {
    if (!mounted) return;
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

  Widget _buildGuideCard(BuildContext context, VoiceProvider voiceProvider) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.accentMint.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lightbulb_outline, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'voice.instructions'.tr(),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStepChip(
                context,
                number: 1,
                icon: Icons.volume_up,
                label: 'voice.listen'.tr(),
                active: _isPreparingExample || _isPlaying,
                done: voiceProvider.lastAudioSynthesis != null,
              ),
              _buildStepChip(
                context,
                number: 2,
                icon: Icons.mic,
                label: 'voice.speak'.tr(),
                active: _isRecording,
                done: _lastRecordingAudioData != null,
              ),
              _buildStepChip(
                context,
                number: 3,
                icon: Icons.insights,
                label: 'voice.pronunciation'.tr(),
                active: _isProcessing,
                done: voiceProvider.lastPronunciationScore != null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepChip(
    BuildContext context, {
    required int number,
    required IconData icon,
    required String label,
    required bool active,
    required bool done,
  }) {
    final color = done
        ? AppColors.greenSuccessBright
        : active
        ? AppColors.primary
        : AppColors.textGrey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: done || active ? 0.12 : 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$number',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Icon(done ? Icons.check_circle : icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhraseSection(
    BuildContext context,
    VoiceProvider voiceProvider,
  ) {
    final selectedPhrase = _phraseController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _phraseController,
          enabled: !_isRecording && !_isBusy,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'voice.phraseToPractice'.tr(),
            hintText: 'voice.enterPhraseHint'.tr(),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
            prefixIcon: const Icon(Icons.short_text),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _isRecording || _isBusy
                  ? null
                  : () {
                      _phraseController.clear();
                      _lastRecordingAudioData = null;
                      voiceProvider.clearResults();
                    },
            ),
          ),
          onChanged: (_) {
            _lastRecordingAudioData = null;
            voiceProvider.clearResults();
          },
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _samplePhrases.take(4).map((phrase) {
              final selected = phrase == selectedPhrase;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(phrase),
                  avatar: selected ? const Icon(Icons.check, size: 16) : null,
                  backgroundColor: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : Theme.of(context).cardColor,
                  side: BorderSide(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.35)
                        : AppColors.grey300,
                  ),
                  onPressed: _isRecording || _isBusy
                      ? null
                      : () {
                          setState(() {
                            _phraseController.text = phrase;
                            _lastRecordingAudioData = null;
                          });
                          voiceProvider.clearResults();
                        },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildListenControls(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isRecording || _isProcessing || _isPreparingExample
                ? null
                : (_isPlaying ? _stopPlaying : _playExample),
            icon: _isPreparingExample
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.surface,
                    ),
                  )
                : Icon(_isPlaying ? Icons.stop : Icons.volume_up),
            label: Text(
              _isPreparingExample
                  ? 'voice.processing'.tr()
                  : (_isPlaying
                        ? 'voice.stop'.tr()
                        : 'voice.listenToExample'.tr()),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        IconButton(
          onPressed: _isRecording || _isBusy ? null : _selectRandomPhrase,
          icon: const Icon(Icons.shuffle),
          tooltip: 'voice.randomPhrase'.tr(),
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            foregroundColor: AppColors.primary,
            minimumSize: const Size(50, 50),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingSection(
    BuildContext context,
    VoiceProvider voiceProvider,
  ) {
    final status = _isProcessing
        ? 'voice.analyzingPronunciation'.tr()
        : (_isRecording
              ? 'voice.recording'.tr()
              : (voiceProvider.lastPronunciationScore != null
                    ? 'voice.goodJob'.tr()
                    : 'voice.tapToRecord'.tr()));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.grey300.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'voice.yourTurn'.tr(),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color:
                    (_isRecording ? AppColors.errorBright : AppColors.primary)
                        .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _isRecording
                      ? AppColors.errorBright
                      : AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!_hasRecorderPermission)
            ElevatedButton.icon(
              onPressed: _checkPermission,
              icon: const Icon(Icons.mic_off),
              label: Text('voice.grantMicrophonePermission'.tr()),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange,
                foregroundColor: Colors.white,
              ),
            )
          else if (_isProcessing)
            _buildProcessingState(context)
          else
            RecordButton(
              isRecording: _isRecording,
              isProcessing: false,
              recordingDuration: _recordingDuration,
              maxDuration: _maxRecordingDuration,
              onPressed: _isRecording ? _stopRecording : _startRecording,
            ),
        ],
      ),
    );
  }

  Widget _buildProcessingState(BuildContext context) {
    return Column(
      children: [
        const LottieAnimationWidget.pulse(width: 92, height: 92),
        const SizedBox(height: 6),
        Text(
          'voice.analyzingPronunciation'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.textGrey,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildErrorCard(BuildContext context, VoiceProvider voiceProvider) {
    final canRetry =
        _lastRecordingAudioData != null && !_isBusy && !_isRecording;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.errorBright.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: AppColors.errorBright),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              voiceProvider.errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.errorDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (canRetry)
            TextButton(
              onPressed: _retryAssessment,
              child: Text('voice.tryAgain'.tr()),
            ),
          IconButton(
            onPressed: voiceProvider.resetState,
            icon: const Icon(Icons.close),
            color: AppColors.errorDark,
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptionCard(
    BuildContext context,
    VoiceProvider voiceProvider,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'voice.youSaid'.tr(),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: AppColors.textGrey),
          ),
          const SizedBox(height: 8),
          Text(
            voiceProvider.lastTranscription!.text,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('voice.practiceTitle'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.shuffle),
            onPressed: _isBusy || _isRecording ? null : _selectRandomPhrase,
            tooltip: 'voice.randomPhrase'.tr(),
          ),
        ],
      ),
      body: Consumer<VoiceProvider>(
        builder: (context, voiceProvider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildGuideCard(context, voiceProvider),
                const SizedBox(height: 24),
                _buildPhraseSection(context, voiceProvider),
                const SizedBox(height: 18),
                _buildListenControls(context),
                const SizedBox(height: 24),
                _buildRecordingSection(context, voiceProvider),
                if (voiceProvider.hasError &&
                    voiceProvider.errorMessage != null) ...[
                  const SizedBox(height: 18),
                  _buildErrorCard(context, voiceProvider),
                ],
                if (voiceProvider.lastTranscription != null &&
                    voiceProvider.lastPronunciationScore == null) ...[
                  const SizedBox(height: 18),
                  _buildTranscriptionCard(context, voiceProvider),
                ],
                if (voiceProvider.lastPronunciationScore != null) ...[
                  const SizedBox(height: 24),
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
                      setState(() => _lastRecordingAudioData = null);
                      voiceProvider.clearResults();
                    },
                    onListenExample: _playExample,
                  ),
                ],
                const SizedBox(height: 28),
              ],
            ),
          );
        },
      ),
    );
  }
}
