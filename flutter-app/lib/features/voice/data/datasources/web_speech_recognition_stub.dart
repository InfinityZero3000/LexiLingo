/// Stub for Web Speech Recognition on non-web platforms
/// This file is used when compiling for mobile/desktop platforms

class WebSpeechRecognition {
  static bool get isSupported => false;

  bool initialize({
    String language = 'en-US',
    bool continuous = false,
    bool interimResults = true,
  }) {
    return false;
  }

  Stream<WebSpeechResult> startListening({String language = 'en-US'}) {
    throw UnsupportedError('Web Speech Recognition is only available on web platform');
  }

  void stopListening() {}

  void abort() {}

  bool get isListening => false;

  Stream<String>? get errorStream => null;

  void dispose() {}
}

class WebSpeechResult {
  final String transcript;
  final double confidence;
  final bool isFinal;

  WebSpeechResult({
    required this.transcript,
    required this.confidence,
    required this.isFinal,
  });
}
