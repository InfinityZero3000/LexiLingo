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

typedef StartLessonRecording = Future<void> Function();
typedef StopLessonRecording = Future<Uint8List> Function();
typedef TranscribeLessonAudio = Future<String> Function(Uint8List audioData);

enum _SpeakingRecorderState { idle, recording, processing, rejected, approved }

class LessonSpeakingRecorder extends StatefulWidget {
  final String targetText;
  final bool isAnswered;
  final ValueChanged<String> onApproved;
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
        'Vui lòng cấp quyền microphone trong cài đặt trình duyệt hoặc thiết bị.',
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
        throw StateError('Không đọc được dữ liệu ghi âm. Vui lòng thử lại.');
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

      if (match.isApproved) {
        widget.onApproved(transcript.trim());
      }
    } catch (error) {
      _showError(_friendlyRecordingError(error));
    }
  }

  Future<Uint8List> _stopDefaultRecording() async {
    final path = await _recorder.stop();
    if (path == null || path.isEmpty) {
      throw StateError('Không nhận được file ghi âm. Vui lòng thử lại.');
    }

    if (kIsWeb) {
      final uri = Uri.tryParse(path);
      if (uri == null) {
        throw StateError('Đường dẫn ghi âm không hợp lệ.');
      }
      final response = await http.get(uri);
      if (response.statusCode != 200) {
        throw StateError('Không đọc được file ghi âm từ trình duyệt.');
      }
      return response.bodyBytes;
    }

    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Không tìm thấy file ghi âm.');
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
        provider.errorMessage ?? 'Không thể nhận dạng giọng nói.',
      );
    }
    if (result.text.trim().isEmpty) {
      throw StateError('Không nghe rõ nội dung. Vui lòng nói lại.');
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
      return 'Vui lòng cấp quyền microphone rồi thử lại.';
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
          label: _isRecording ? 'Dừng ghi âm' : 'Bắt đầu ghi âm',
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
            'Đã nghe: "$_transcript"',
            style: TextStyle(fontSize: 12, color: secondary),
            textAlign: TextAlign.center,
          ),
        ],
        if (_similarity != null && !_isApproved) ...[
          const SizedBox(height: 4),
          Text(
            'Mức khớp: ${(_similarity! * 100).round()}%',
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
        return 'Nhấn để bắt đầu nói';
      case _SpeakingRecorderState.recording:
        return 'Đang ghi âm - nhấn để dừng';
      case _SpeakingRecorderState.processing:
        return 'Đang nhận dạng giọng nói...';
      case _SpeakingRecorderState.rejected:
        return 'Chưa khớp, hãy thử lại';
      case _SpeakingRecorderState.approved:
        return 'Bạn đã nói đúng';
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
