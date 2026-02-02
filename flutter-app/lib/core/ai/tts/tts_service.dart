import 'dart:typed_data';
import '../../utils/app_logger.dart';

/// Text-to-Speech service interface
/// Implementation should use Piper VITS for natural, offline TTS
/// 
/// Architecture specs:
/// - Model: en_US-lessac-medium (VITS-based)
/// - Size: 30-60MB
/// - Latency: 100-300ms
/// - Output: 22kHz WAV/MP3
/// - Features: Natural prosody, adjustable speed, offline capable
abstract class TTSService {
  /// Initialize the TTS service
  /// Should load the Piper VITS model
  Future<void> initialize();

  /// Synthesize text to audio
  /// 
  /// [text] - Text to convert to speech
  /// [speed] - Speech rate (0.5 = slow, 1.0 = normal, 2.0 = fast)
  /// [cacheKey] - Optional key for caching common phrases
  /// 
  /// Returns audio bytes (WAV format)
  Future<Uint8List> synthesize({
    required String text,
    double speed = 1.0,
    String? cacheKey,
  });

  /// Get cached audio if available
  /// Used for common phrases like "Great job!", "Try again"
  Uint8List? getCached(String cacheKey);

  /// Pre-generate and cache common phrases
  Future<void> preGenerateCommonPhrases();

  /// Check if the service is ready
  bool get isReady;

  /// Get model information
  TTSModelInfo get modelInfo;

  /// Clean up resources
  Future<void> dispose();
}

/// TTS model information
class TTSModelInfo {
  final String name;
  final String voice;
  final int sampleRate;
  final int sizeInMB;

  const TTSModelInfo({
    required this.name,
    required this.voice,
    required this.sampleRate,
    required this.sizeInMB,
  });
}

/// Mock implementation for development/testing
/// TODO: Replace with actual Piper VITS integration
class MockTTSService implements TTSService {
  bool _isInitialized = false;
  final Map<String, Uint8List> _cache = {};

  // Common phrases to pre-generate
  static const _commonPhrases = [
    'Great job!',
    'Try again',
    'Well done',
    'Good effort',
    'Let me explain',
    'Can you repeat that?',
    'Perfect pronunciation',
    'Almost there',
  ];

  @override
  Future<void> initialize() async {
    // Simulate model loading
    await Future.delayed(const Duration(milliseconds: 300));
    _isInitialized = true;
    logDebug('[MockTTS] Initialized (Piper VITS - Mock)');
    
    // Pre-generate common phrases
    await preGenerateCommonPhrases();
  }

  @override
  Future<Uint8List> synthesize({
    required String text,
    double speed = 1.0,
    String? cacheKey,
  }) async {
    if (!_isInitialized) {
      throw StateError('TTS service not initialized');
    }

    // Check cache first
    if (cacheKey != null && _cache.containsKey(cacheKey)) {
      logDebug('[MockTTS] Using cached audio for: "$cacheKey"');
      return _cache[cacheKey]!;
    }

    // Simulate synthesis (100-300ms)
    final latency = 100 + (text.length * 2); // ~2ms per character
    await Future.delayed(Duration(milliseconds: latency.clamp(100, 300)));

    // Generate mock audio data (just placeholder bytes)
    final audioData = Uint8List.fromList(
      List.generate(44100, (i) => (i % 256)), // 1 second at 22kHz (mock)
    );

    // Cache if key provided
    if (cacheKey != null) {
      _cache[cacheKey] = audioData;
    }

    logDebug('[MockTTS] Synthesized: "$text" (${latency}ms, speed: ${speed}x)');
    return audioData;
  }

  @override
  Uint8List? getCached(String cacheKey) {
    return _cache[cacheKey];
  }

  @override
  Future<void> preGenerateCommonPhrases() async {
    logDebug('[MockTTS] Pre-generating ${_commonPhrases.length} common phrases...');
    
    for (final phrase in _commonPhrases) {
      await synthesize(text: phrase, cacheKey: phrase);
    }
    
    logDebug('[MockTTS] Pre-generation complete. Cache size: ${_cache.length}');
  }

  @override
  bool get isReady => _isInitialized;

  @override
  TTSModelInfo get modelInfo => const TTSModelInfo(
        name: 'Piper VITS (Mock)',
        voice: 'en_US-lessac-medium',
        sampleRate: 22050,
        sizeInMB: 45,
      );

  @override
  Future<void> dispose() async {
    _cache.clear();
    _isInitialized = false;
    logDebug('[MockTTS] Disposed');
  }
}
