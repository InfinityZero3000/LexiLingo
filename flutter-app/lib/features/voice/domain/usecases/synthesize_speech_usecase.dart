import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/voice/domain/entities/audio_synthesis.dart';
import 'package:lexilingo_app/features/voice/domain/repositories/voice_repository.dart';

/// Synthesize Speech Use Case
/// Converts text to audio using TTS service
class SynthesizeSpeechUseCase implements UseCase<AudioSynthesis, SynthesizeParams> {
  final VoiceRepository repository;

  SynthesizeSpeechUseCase(this.repository);

  @override
  Future<Either<Failure, AudioSynthesis>> call(SynthesizeParams params) async {
    return await repository.synthesizeSpeech(
      text: params.text,
    );
  }
}

class SynthesizeParams {
  final String text;

  SynthesizeParams({required this.text});
}
