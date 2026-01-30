/// Platform-aware Speech Recognition Service
/// Uses Web Speech API on web, and provides stub on other platforms
/// 
/// Usage:
/// ```dart
/// import 'package:lexilingo_app/features/voice/data/datasources/speech_recognition_service.dart';
/// 
/// final service = SpeechRecognitionService();
/// if (service.isSupported) {
///   final stream = service.startListening(language: 'en-US');
///   stream.listen((result) {
///     if (result.isFinal) {
///       print('Final: ${result.transcript}');
///     }
///   });
/// }
/// ```

export 'web_speech_recognition_stub.dart'
    if (dart.library.html) 'web_speech_recognition.dart';
