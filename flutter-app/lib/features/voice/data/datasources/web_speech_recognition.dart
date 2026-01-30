// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js' as js;
import 'dart:js_interop';

/// Web Speech Recognition Service
/// Uses browser's native SpeechRecognition API for STT on web platform
class WebSpeechRecognition {
  dynamic _recognition;
  StreamController<WebSpeechResult>? _resultController;
  StreamController<String>? _errorController;
  bool _isListening = false;

  /// Check if Web Speech API is available
  static bool get isSupported {
    return js.context.hasProperty('SpeechRecognition') ||
        js.context.hasProperty('webkitSpeechRecognition');
  }

  /// Get the SpeechRecognition constructor
  dynamic _createRecognition() {
    try {
      // Try standard API first, then webkit prefix (for Chrome/Safari)
      if (js.context.hasProperty('SpeechRecognition')) {
        return js.JsObject(js.context['SpeechRecognition'] as js.JsFunction);
      } else if (js.context.hasProperty('webkitSpeechRecognition')) {
        return js.JsObject(js.context['webkitSpeechRecognition'] as js.JsFunction);
      }
    } catch (e) {
      print('Failed to create SpeechRecognition: $e');
    }
    return null;
  }

  /// Initialize the speech recognition
  bool initialize({
    String language = 'en-US',
    bool continuous = false,
    bool interimResults = true,
  }) {
    _recognition = _createRecognition();
    if (_recognition == null) {
      return false;
    }

    _recognition['lang'] = language;
    _recognition['continuous'] = continuous;
    _recognition['interimResults'] = interimResults;
    _recognition['maxAlternatives'] = 3;

    return true;
  }

  /// Start listening for speech
  Stream<WebSpeechResult> startListening({
    String language = 'en-US',
  }) {
    _resultController?.close();
    _errorController?.close();
    
    _resultController = StreamController<WebSpeechResult>.broadcast();
    _errorController = StreamController<String>.broadcast();

    if (!initialize(language: language)) {
      _resultController!.addError('Speech recognition not supported');
      return _resultController!.stream;
    }

    // Set up event handlers using dart:js_interop
    _recognition['onresult'] = ((dynamic event) {
      _handleResult(event);
    }).toJS;

    _recognition['onerror'] = ((dynamic event) {
      _handleError(event);
    }).toJS;

    _recognition['onend'] = ((dynamic event) {
      _handleEnd();
    }).toJS;

    _recognition['onstart'] = ((dynamic event) {
      _isListening = true;
    }).toJS;

    try {
      _recognition.callMethod('start');
    } catch (e) {
      _resultController!.addError('Failed to start speech recognition: $e');
    }

    return _resultController!.stream;
  }

  /// Handle speech recognition results
  void _handleResult(dynamic event) {
    try {
      final results = event['results'];
      final resultIndex = event['resultIndex'] ?? 0;
      
      for (int i = resultIndex; i < results['length']; i++) {
        final result = results[i];
        final alternative = result[0];
        
        final transcript = alternative['transcript'] as String? ?? '';
        final confidence = (alternative['confidence'] as num?)?.toDouble() ?? 0.0;
        final isFinal = result['isFinal'] as bool? ?? false;

        _resultController?.add(WebSpeechResult(
          transcript: transcript,
          confidence: confidence,
          isFinal: isFinal,
        ));
      }
    } catch (e) {
      print('Error handling result: $e');
    }
  }

  /// Handle speech recognition errors
  void _handleError(dynamic event) {
    final error = event['error'] as String? ?? 'unknown';
    String errorMessage;
    
    switch (error) {
      case 'no-speech':
        errorMessage = 'No speech detected. Please try again.';
        break;
      case 'audio-capture':
        errorMessage = 'Microphone not available. Please check permissions.';
        break;
      case 'not-allowed':
        errorMessage = 'Microphone access denied. Please allow microphone access.';
        break;
      case 'network':
        errorMessage = 'Network error. Please check your connection.';
        break;
      case 'aborted':
        errorMessage = 'Speech recognition aborted.';
        break;
      case 'language-not-supported':
        errorMessage = 'Language not supported.';
        break;
      default:
        errorMessage = 'Speech recognition error: $error';
    }
    
    _resultController?.addError(errorMessage);
    _errorController?.add(errorMessage);
  }

  /// Handle speech recognition end
  void _handleEnd() {
    _isListening = false;
  }

  /// Stop listening
  void stopListening() {
    try {
      _recognition?.callMethod('stop');
    } catch (e) {
      print('Error stopping recognition: $e');
    }
    _isListening = false;
  }

  /// Abort recognition
  void abort() {
    try {
      _recognition?.callMethod('abort');
    } catch (e) {
      print('Error aborting recognition: $e');
    }
    _isListening = false;
  }

  /// Check if currently listening
  bool get isListening => _isListening;

  /// Get error stream
  Stream<String>? get errorStream => _errorController?.stream;

  /// Dispose resources
  void dispose() {
    stopListening();
    _resultController?.close();
    _errorController?.close();
    _recognition = null;
  }
}

/// Result from Web Speech Recognition
class WebSpeechResult {
  final String transcript;
  final double confidence;
  final bool isFinal;

  WebSpeechResult({
    required this.transcript,
    required this.confidence,
    required this.isFinal,
  });

  @override
  String toString() => 'WebSpeechResult(transcript: $transcript, confidence: $confidence, isFinal: $isFinal)';
}
