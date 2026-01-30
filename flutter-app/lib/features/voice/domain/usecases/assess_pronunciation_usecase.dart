import 'dart:typed_data';
import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/voice/domain/entities/pronunciation_score.dart';
import 'package:lexilingo_app/features/voice/domain/repositories/voice_repository.dart';

/// Assess Pronunciation Use Case
/// Compares user's pronunciation against target text
class AssessPronunciationUseCase implements UseCase<PronunciationScore, AssessPronunciationParams> {
  final VoiceRepository repository;

  AssessPronunciationUseCase(this.repository);

  @override
  Future<Either<Failure, PronunciationScore>> call(AssessPronunciationParams params) async {
    return await repository.assessPronunciation(
      audioData: params.audioData,
      filename: params.filename,
      targetText: params.targetText,
      language: params.language,
    );
  }
}

class AssessPronunciationParams {
  final Uint8List audioData;
  final String filename;
  final String targetText;
  final String? language;

  AssessPronunciationParams({
    required this.audioData,
    required this.filename,
    required this.targetText,
    this.language,
  });
}
