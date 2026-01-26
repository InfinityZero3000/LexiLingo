import 'dart:typed_data';

/// Speech-to-Text service interface
/// Implementation should use Faster-Whisper v3 for optimal performance
/// 
/// Architecture specs:
/// - Model: openai/whisper-small (244MB)
/// - Backend: CTranslate2 optimization
/// - Features: VAD (Silero), streaming, word timestamps
/// - Performance: WER <10%, RTF <0.3, Latency <100ms
abstract class STTService {
  /// Initialize the STT service
  /// Should load the Whisper model and VAD
  Future<void> initialize();

  /// Transcribe audio bytes to text
  /// 
  /// [audioBytes] - Raw audio data (WAV format, 16kHz recommended)
  /// [language] - Target language code (default: 'en')
  /// [withTimestamps] - Include word-level timestamps for pronunciation alignment
  /// 
  /// Returns [TranscriptionResult] with text and optional timestamps
  Future<TranscriptionResult> transcribe({
    required Uint8List audioBytes,
    String language = 'en',
    bool withTimestamps = false,
  });

  /// Stream transcription for real-time processing
  /// Useful for live conversation practice
  Stream<TranscriptionResult> transcribeStream({
    required Stream<Uint8List> audioStream,
    String language = 'en',
  });

  /// Check if the service is ready
  bool get isReady;

  /// Get model information
  ModelInfo get modelInfo;

  /// Clean up resources
  Future<void> dispose();
}

/// Result of transcription
class TranscriptionResult {
  /// Transcribed text
  final String text;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  /// Word-level timestamps (optional, for pronunciation alignment)
  final List<WordTimestamp>? wordTimestamps;

  /// Processing time in milliseconds
  final int processingTimeMs;

  const TranscriptionResult({
    required this.text,
    required this.confidence,
    this.wordTimestamps,
    required this.processingTimeMs,
  });

  @override
  String toString() {
    return 'TranscriptionResult(text: "$text", confidence: $confidence, '
        'time: ${processingTimeMs}ms, words: ${wordTimestamps?.length ?? 0})';
  }
}

/// Word timestamp for pronunciation alignment
class WordTimestamp {
  final String word;
  final double startTime; // in seconds
  final double endTime; // in seconds
  final double confidence;

  const WordTimestamp({
    required this.word,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  double get duration => endTime - startTime;
}

/// Model information
class ModelInfo {
  final String name;
  final String version;
  final int sizeInMB;
  final List<String> supportedLanguages;

  const ModelInfo({
    required this.name,
    required this.version,
    required this.sizeInMB,
    required this.supportedLanguages,
  });
}

/// Mock implementation for development/testing
/// TODO: Replace with actual Faster-Whisper integration
class MockSTTService implements STTService {
  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    // Simulate model loading
    await Future.delayed(const Duration(milliseconds: 500));
    _isInitialized = true;
    print('[MockSTT] Initialized (Faster-Whisper v3 - Mock)');
  }

  @override
  Future<TranscriptionResult> transcribe({
    required Uint8List audioBytes,
    String language = 'en',
    bool withTimestamps = false,
  }) async {
    if (!_isInitialized) {
      throw StateError('STT service not initialized');
    }

    // Simulate processing
    final startTime = DateTime.now();
    await Future.delayed(const Duration(milliseconds: 80));

    // Mock transcription result
    final mockText = 'I am go to the kitchen for coffee';
    final processingTime =
        DateTime.now().difference(startTime).inMilliseconds;

    final wordTimestamps = withTimestamps
        ? [
            const WordTimestamp(
                word: 'I', startTime: 0.0, endTime: 0.2, confidence: 0.95),
            const WordTimestamp(
                word: 'am', startTime: 0.2, endTime: 0.4, confidence: 0.92),
            const WordTimestamp(
                word: 'go', startTime: 0.4, endTime: 0.6, confidence: 0.88),
            const WordTimestamp(
                word: 'to', startTime: 0.6, endTime: 0.75, confidence: 0.94),
            const WordTimestamp(
                word: 'the', startTime: 0.75, endTime: 0.9, confidence: 0.96),
            const WordTimestamp(
                word: 'kitchen',
                startTime: 0.9,
                endTime: 1.3,
                confidence: 0.93),
            const WordTimestamp(
                word: 'for', startTime: 1.3, endTime: 1.5, confidence: 0.91),
            const WordTimestamp(
                word: 'coffee',
                startTime: 1.5,
                endTime: 2.0,
                confidence: 0.94),
          ]
        : null;

    return TranscriptionResult(
      text: mockText,
      confidence: 0.92,
      wordTimestamps: wordTimestamps,
      processingTimeMs: processingTime,
    );
  }

  @override
  Stream<TranscriptionResult> transcribeStream({
    required Stream<Uint8List> audioStream,
    String language = 'en',
  }) async* {
    // Mock streaming transcription
    await for (final chunk in audioStream) {
      yield await transcribe(audioBytes: chunk, language: language);
    }
  }

  @override
  bool get isReady => _isInitialized;

  @override
  ModelInfo get modelInfo => const ModelInfo(
        name: 'Faster-Whisper v3 (Mock)',
        version: '3.0.0',
        sizeInMB: 244,
        supportedLanguages: ['en', 'vi', 'es', 'fr', 'de', 'it', 'pt', 'ru'],
      );

  @override
  Future<void> dispose() async {
    _isInitialized = false;
    print('[MockSTT] Disposed');
  }
}
