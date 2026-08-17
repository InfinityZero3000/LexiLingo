import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/skill_event_recorder.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/voice/domain/entities/audio_synthesis.dart';
import 'package:lexilingo_app/features/voice/domain/entities/pronunciation_score.dart';
import 'package:lexilingo_app/features/voice/domain/entities/transcription.dart';
import 'package:lexilingo_app/features/voice/domain/usecases/assess_pronunciation_usecase.dart';
import 'package:lexilingo_app/features/voice/domain/usecases/synthesize_speech_usecase.dart';
import 'package:lexilingo_app/features/voice/domain/usecases/transcribe_audio_usecase.dart';

enum VoiceState { idle, recording, processing, playing, error }

/// Voice Provider
/// Manages state for voice recording, playback, and pronunciation assessment
class VoiceProvider extends ChangeNotifier {
  final TranscribeAudioUseCase transcribeAudioUseCase;
  final SynthesizeSpeechUseCase synthesizeSpeechUseCase;
  final AssessPronunciationUseCase assessPronunciationUseCase;
  final SkillEventRecorder skillRecorder;

  VoiceProvider({
    this.skillRecorder = const SkillEventRecorder(),
    required this.transcribeAudioUseCase,
    required this.synthesizeSpeechUseCase,
    required this.assessPronunciationUseCase,
  });

  VoiceState _state = VoiceState.idle;
  String? _errorMessage;
  Transcription? _lastTranscription;
  AudioSynthesis? _lastAudioSynthesis;
  PronunciationScore? _lastPronunciationScore;
  Duration _recordingDuration = Duration.zero;

  // Getters
  VoiceState get state => _state;
  String? get errorMessage => _errorMessage;
  Transcription? get lastTranscription => _lastTranscription;
  AudioSynthesis? get lastAudioSynthesis => _lastAudioSynthesis;
  PronunciationScore? get lastPronunciationScore => _lastPronunciationScore;
  Duration get recordingDuration => _recordingDuration;

  bool get isIdle => _state == VoiceState.idle;
  bool get isRecording => _state == VoiceState.recording;
  bool get isProcessing => _state == VoiceState.processing;
  bool get isPlaying => _state == VoiceState.playing;
  bool get hasError => _state == VoiceState.error;

  /// Start recording audio
  void startRecording() {
    _state = VoiceState.recording;
    _recordingDuration = Duration.zero;
    _errorMessage = null;
    notifyListeners();
  }

  /// Update recording duration (called periodically during recording)
  void updateRecordingDuration(Duration duration) {
    _recordingDuration = duration;
    notifyListeners();
  }

  /// Stop recording and transcribe audio
  Future<Transcription?> stopRecordingAndTranscribe({
    required Uint8List audioData,
    required String filename,
    String? language,
  }) async {
    _state = VoiceState.processing;
    notifyListeners();

    final result = await transcribeAudioUseCase(
      TranscribeParams(
        audioData: audioData,
        filename: filename,
        language: language,
      ),
    );

    return result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
        _state = VoiceState.error;
        notifyListeners();
        return null;
      },
      (transcription) {
        _lastTranscription = transcription;
        _state = VoiceState.idle;
        notifyListeners();
        return transcription;
      },
    );
  }

  /// Synthesize text to speech and play
  Future<AudioSynthesis?> synthesizeAndPlay({required String text}) async {
    if (text.isEmpty) {
      _errorMessage = 'Text cannot be empty';
      _state = VoiceState.error;
      notifyListeners();
      return null;
    }

    _state = VoiceState.processing;
    _errorMessage = null;
    notifyListeners();

    final result = await synthesizeSpeechUseCase(SynthesizeParams(text: text));

    return result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
        _state = VoiceState.error;
        notifyListeners();
        return null;
      },
      (audioSynthesis) {
        _lastAudioSynthesis = audioSynthesis;
        _state = VoiceState.playing;
        notifyListeners();
        return audioSynthesis;
      },
    );
  }

  /// Mark playback as complete
  void onPlaybackComplete() {
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Assess pronunciation against target text
  Future<PronunciationScore?> assessPronunciation({
    required Uint8List audioData,
    required String filename,
    required String targetText,
    String? language,
  }) async {
    if (targetText.isEmpty) {
      _errorMessage = 'Target text cannot be empty';
      _state = VoiceState.error;
      notifyListeners();
      return null;
    }

    _state = VoiceState.processing;
    _errorMessage = null;
    notifyListeners();

    final result = await assessPronunciationUseCase(
      AssessPronunciationParams(
        audioData: audioData,
        filename: filename,
        targetText: targetText,
        language: language,
      ),
    );

    return result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
        _state = VoiceState.error;
        notifyListeners();
        return null;
      },
      (score) {
        _lastPronunciationScore = score;
        _state = VoiceState.idle;
        notifyListeners();
        unawaited(_recordSpeakingEvidence(score));
        return score;
      },
    );
  }

  /// Send an assessed attempt to the speaking skill score, and put the words
  /// that came out badly on the review schedule.
  ///
  /// The assessment used to be shown and then discarded: a learner could
  /// record twenty phrases and the app would know no more about their
  /// speaking than before they started.
  Future<void> _recordSpeakingEvidence(PronunciationScore score) async {
    // 70 is the entity's own isNeedsWork boundary — keep the two together so
    // "needs work" in the UI and "incorrect" in the model never disagree.
    const passMark = 70;

    final results = <ExerciseResultData>[
      ExerciseResultData(
        exerciseType: 'pronunciation',
        skill: SkillType.speaking,
        difficultyLevel: _assessmentLevel,
        isCorrect: score.overallScore >= passMark,
        score: score.overallScore.toDouble(),
      ),
    ];

    for (final word in score.wordScores) {
      if (word.score >= passMark && !word.hasIssue) continue;
      final conceptId = vocabConceptId(word.word);
      if (conceptId == null) continue;
      results.add(
        ExerciseResultData(
          exerciseType: 'pronunciation_word',
          skill: SkillType.speaking,
          difficultyLevel: _assessmentLevel,
          isCorrect: false,
          score: word.score.toDouble(),
          conceptId: conceptId,
        ),
      );
    }

    await skillRecorder.record(results);
  }

  /// The assessment API returns no CEFR level of its own, and the practice
  /// phrases are not levelled either, so every attempt is recorded at the
  /// middle band rather than pretending to a precision we do not have.
  static const String _assessmentLevel = 'B1';

  /// Clear last result
  void clearResults() {
    _lastTranscription = null;
    _lastAudioSynthesis = null;
    _lastPronunciationScore = null;
    _errorMessage = null;
    _state = VoiceState.idle;
    notifyListeners();
  }

  /// Reset state to idle
  void resetState() {
    _state = VoiceState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  String _getFailureMessage(Failure failure) {
    if (failure is ServerFailure) {
      return failure.message;
    } else if (failure is NetworkFailure) {
      return 'Network error. Please check your connection.';
    } else {
      return 'An unexpected error occurred.';
    }
  }
}
