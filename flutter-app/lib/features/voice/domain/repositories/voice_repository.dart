import 'dart:typed_data';
import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/voice/domain/entities/audio_synthesis.dart';
import 'package:lexilingo_app/features/voice/domain/entities/transcription.dart';
import 'package:lexilingo_app/features/voice/domain/entities/pronunciation_score.dart';

/// Voice Repository Interface
/// Defines the contract for voice-related operations
abstract class VoiceRepository {
  /// Transcribe audio file to text (STT)
  /// [audioData] - raw audio bytes (wav/mp3/m4a)
  /// [language] - optional language hint (e.g., 'en', 'vi')
  Future<Either<Failure, Transcription>> transcribeAudio({
    required Uint8List audioData,
    required String filename,
    String? language,
  });

  /// Synthesize text to speech (TTS)
  /// [text] - text to convert to speech
  Future<Either<Failure, AudioSynthesis>> synthesizeSpeech({
    required String text,
  });

  /// Assess pronunciation by comparing user audio against target text
  /// Uses AI to analyze pronunciation quality
  Future<Either<Failure, PronunciationScore>> assessPronunciation({
    required Uint8List audioData,
    required String filename,
    required String targetText,
    String? language,
  });
}
