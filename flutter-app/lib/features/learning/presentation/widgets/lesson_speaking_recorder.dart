import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../voice/presentation/providers/voice_provider.dart';
import '../../domain/services/speaking_answer_matcher.dart';
import 'package:easy_localization/easy_localization.dart';

typedef StartLessonRecording = Future<void> Function();
typedef StopLessonRecording = Future<Uint8List> Function();
typedef TranscribeLessonAudio = Future<String> Function(Uint8List audioData);

enum _SpeakingRecorderState { idle, recording, processing, rejected, approved }

class LessonSpeakingRecorder extends StatefulWidget {
  final String targetText;
  final bool isAnswered;
  final ValueChanged<String> onApproved;

  /// Every take, approved or not, reports the best transcript so far. Without
  /// it a rejected take submits nothing, the learner re-records until they
  /// pass, and the pipeline only ever sees successes — speaking accuracy is
  /// then 100% by construction rather than by ability.
  final ValueChanged<String>? onAttempt;
  final Color? primaryColor;
  final Color? secondaryTextColor;
  final StartLessonRecording? startRecording;
  final StopLessonRecording? stopRecording;
  final TranscribeLessonAudio? transcribeAudio;

  const LessonSpeakingRecorder({
    super.key,
    required this.targetText,
    required this.isAnswered,
    required this.onApproved,
    this.onAttempt,
    this.primaryColor,
    this.secondaryTextColor,
    this.startRecording,
    this.stopRecording,
    this.transcribeAudio,
  });

  @override
  State<LessonSpeakingRecorder> createState() => _LessonSpeakingRecorderState();
}

class _LessonSpeakingRecorderState extends State<LessonSpeakingRecorder> {
  final AudioRecorder _recorder = AudioRecorder();

  _SpeakingRecorderState _state = _SpeakingRecorderState.idle;
  Timer? _timer;
  Duration _duration = Duration.zero;
  String? _transcript;
  String? _errorMessage;
  double? _similarity;
  String? _bestTranscript;
  double _bestSimilarity = -1;

  bool get _isRecording => _state == _SpeakingRecorderState.recording;
  bool get _isProcessing => _state == _SpeakingRecorderState.processing;
  bool get _isApproved =>
      _state == _SpeakingRecorderState.approved || widget.isAnswered;

  @override
  void didUpdateWidget(covariant LessonSpeakingRecorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetText != widget.targetText) {
      _timer?.cancel();
      _duration = Duration.zero;
      _transcript = null;
      _errorMessage = null;
      _similarity = null;
      _bestTranscript = null;
      _bestSimilarity = -1;
      _state = _SpeakingRecorderState.idle;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_releaseRecorder());
    super.dispose();
  }

  Future<void> _releaseRecorder() async {
    if (_isRecording) {
      await _recorder.stop();
    }
    await _recorder.dispose();
  }

  Future<void> _handleTap() async {
    if (_isProcessing || _isApproved) return;
    if (_isRecording) {
      await _stopAndEvaluate();
    } else {
      await _start();
    }
  }

  Future<void> _start() async {
    try {
      if (widget.startRecording != null) {
        await widget.startRecording!();
      } else {
        await _startDefaultRecording();
      }

      if (!mounted) return;
      setState(() {
        _state = _SpeakingRecorderState.recording;
        _duration = Duration.zero;
        _transcript = null;
        _errorMessage = null;
        _similarity = null;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _duration += const Duration(seconds: 1));
      });
    } catch (error) {
      _showError(_friendlyRecordingError(error));
    }
  }

  Future<void> _startDefaultRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError(
        'voice.micPermissionSettings'.tr(),
      );
    }

    String path;
    if (kIsWeb) {
      path = 'lesson_speaking_${DateTime.now().millisecondsSinceEpoch}.wav';
    } else {
      final directory = await getTemporaryDirectory();
      path =
          '${directory.path}/lesson_speaking_${DateTime.now().millisecondsSinceEpoch}.wav';
    }

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        numChannels: 1,
        sampleRate: 16000,
      ),
      path: path,
    );
  }

  Future<void> _stopAndEvaluate() async {
    _timer?.cancel();
    if (mounted) {
      setState(() => _state = _SpeakingRecorderState.processing);
    }

    try {
      final audioData = widget.stopRecording != null
          ? await widget.stopRecording!()
          : await _stopDefaultRecording();
      if (audioData.isEmpty) {
        throw StateError('voice.recordingUnreadable'.tr());
      }

      final transcript = widget.transcribeAudio != null
          ? await widget.transcribeAudio!(audioData)
          : await _transcribeWithVoiceProvider(audioData);
      final match = SpeakingAnswerMatcher.evaluate(
        transcript: transcript,
        target: widget.targetText,
      );

      if (!mounted) return;
      setState(() {
        _transcript = transcript.trim();
        _similarity = match.similarity;
        _errorMessage = null;
        _state = match.isApproved
            ? _SpeakingRecorderState.approved
            : _SpeakingRecorderState.rejected;
      });

      final spoken = transcript.trim();
      if (match.similarity > _bestSimilarity) {
        _bestSimilarity = match.similarity;
        _bestTranscript = spoken;
      }

      if (match.isApproved) {
        widget.onApproved(spoken);
      } else {
        // Offer the best take so far as the answer. The learner keeps
        // retrying; if they move on instead, what they managed is recorded
        // rather than discarded.
        widget.onAttempt?.call(_bestTranscript ?? spoken);
      }
    } catch (error) {
      _showError(_friendlyRecordingError(error));
    }
  }

  Future<Uint8List> _stopDefaultRecording() async {
    final path = await _recorder.stop();
    if (path == null || path.isEmpty) {
      throw StateError('voice.recordingMissing'.tr());
    }

    if (kIsWeb) {
      final uri = Uri.tryParse(path);
      if (uri == null) {
        throw StateError('voice.recordingPathInvalid'.tr());
      }
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw StateError('voice.recordingBrowserUnreadable'.tr());
      }
      return response.bodyBytes;
    }

    final file = File(path);
    if (!await file.exists()) {
      throw StateError('voice.recordingNotFound'.tr());
    }
    return file.readAsBytes();
  }

  Future<String> _transcribeWithVoiceProvider(Uint8List audioData) async {
    final provider = context.read<VoiceProvider>();
    final result = await provider.stopRecordingAndTranscribe(
      audioData: audioData,
      filename: 'lesson_recording.wav',
      language: 'en',
    );
    if (result == null) {
      throw StateError(
        provider.errorMessage ?? 'voice.speechNotRecognized'.tr(),
      );
    }
    if (result.text.trim().isEmpty) {
      throw StateError('voice.speechUnclear'.tr());
    }
    return result.text;
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _state = _SpeakingRecorderState.rejected;
      _errorMessage = message;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _friendlyRecordingError(Object error) {
    final message = error.toString().replaceFirst('Bad state: ', '');
    if (message.toLowerCase().contains('permission')) {
      return 'voice.micPermissionRetry'.tr();
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    final primary =
        widget.primaryColor ?? Theme.of(context).colorScheme.primary;
    final secondary =
        widget.secondaryTextColor ??
        Theme.of(context).colorScheme.onSurfaceVariant;
    final active = _isRecording || _isApproved;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: _isRecording ? 'voice.stopRecording'.tr() : 'voice.startRecording'.tr(),
          child: GestureDetector(
            key: const Key('lesson-speaking-mic'),
            onTap: _handleTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? primary : Colors.transparent,
                border: Border.all(color: primary, width: 2.5),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ]
                    : const [],
              ),
              child: _isProcessing
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: primary,
                      ),
                    )
                  : Icon(
                      _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      size: 36,
                      color: active ? Colors.white : primary,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _statusLabel,
          style: TextStyle(
            fontSize: 13,
            color: _state == _SpeakingRecorderState.rejected
                ? Colors.red
                : secondary,
            fontWeight: _isApproved || _state == _SpeakingRecorderState.rejected
                ? FontWeight.w600
                : FontWeight.normal,
          ),
          textAlign: TextAlign.center,
        ),
        if (_isRecording) ...[
          const SizedBox(height: 4),
          Text(
            _formattedDuration,
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
        if (_transcript != null && _transcript!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${'voice.youSaid'.tr()} "$_transcript"',
            style: TextStyle(fontSize: 12, color: secondary),
            textAlign: TextAlign.center,
          ),
        ],
        if (_similarity != null && !_isApproved) ...[
          const SizedBox(height: 4),
          Text(
            'voice.matchPercent'.tr(namedArgs: {'percent': '${(_similarity! * 100).round()}'}),
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 12, color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  String get _statusLabel {
    switch (_state) {
      case _SpeakingRecorderState.idle:
        return 'voice.tapToStartSpeaking'.tr();
      case _SpeakingRecorderState.recording:
        return 'voice.recordingTapToStop'.tr();
      case _SpeakingRecorderState.processing:
        return 'voice.recognizing'.tr();
      case _SpeakingRecorderState.rejected:
        return 'voice.notMatchedTryAgain'.tr();
      case _SpeakingRecorderState.approved:
        return 'voice.saidCorrectly'.tr();
    }
  }

  String get _formattedDuration {
    final minutes = _duration.inMinutes
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    final seconds = _duration.inSeconds
        .remainder(60)
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
