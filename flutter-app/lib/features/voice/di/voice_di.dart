import 'package:get_it/get_it.dart';
import 'package:lexilingo_app/features/voice/data/datasources/voice_remote_datasource.dart';
import 'package:lexilingo_app/features/voice/data/repositories/voice_repository_impl.dart';
import 'package:lexilingo_app/features/voice/domain/repositories/voice_repository.dart';
import 'package:lexilingo_app/features/voice/domain/usecases/assess_pronunciation_usecase.dart';
import 'package:lexilingo_app/features/voice/domain/usecases/synthesize_speech_usecase.dart';
import 'package:lexilingo_app/features/voice/domain/usecases/transcribe_audio_usecase.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/voice_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';

/// Voice Feature Dependency Injection
/// Registers all voice-related dependencies
void initVoiceDependencies(GetIt sl) {
  // Providers
  sl.registerFactory<VoiceProvider>(
    () => VoiceProvider(
      transcribeAudioUseCase: sl(),
      synthesizeSpeechUseCase: sl(),
      assessPronunciationUseCase: sl(),
    ),
  );
  
  // TTS Settings Provider (Singleton - persists settings)
  sl.registerLazySingleton<TtsSettingsProvider>(
    () => TtsSettingsProvider(),
  );

  // Use Cases
  sl.registerLazySingleton<TranscribeAudioUseCase>(
    () => TranscribeAudioUseCase(sl()),
  );
  sl.registerLazySingleton<SynthesizeSpeechUseCase>(
    () => SynthesizeSpeechUseCase(sl()),
  );
  sl.registerLazySingleton<AssessPronunciationUseCase>(
    () => AssessPronunciationUseCase(sl()),
  );

  // Repository
  sl.registerLazySingleton<VoiceRepository>(
    () => VoiceRepositoryImpl(
      remoteDataSource: sl(),
      networkInfo: sl(),
    ),
  );

  // Data Sources
  sl.registerLazySingleton<VoiceRemoteDataSource>(
    () => VoiceRemoteDataSourceImpl(),
  );
}
