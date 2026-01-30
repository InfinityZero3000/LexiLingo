import 'dart:typed_data';
import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/voice/domain/entities/transcription.dart';
import 'package:lexilingo_app/features/voice/domain/repositories/voice_repository.dart';

/// Transcribe Audio Use Case
/// Converts audio recording to text using STT service
class TranscribeAudioUseCase implements UseCase<Transcription, TranscribeParams> {
  final VoiceRepository repository;

  TranscribeAudioUseCase(this.repository);

  @override
  Future<Either<Failure, Transcription>> call(TranscribeParams params) async {
    return await repository.transcribeAudio(
      audioData: params.audioData,
      filename: params.filename,
      language: params.language,
    );
  }
}

class TranscribeParams {
  final Uint8List audioData;
  final String filename;
  final String? language;

  TranscribeParams({
    required this.audioData,
    required this.filename,
    this.language,
  });
}
