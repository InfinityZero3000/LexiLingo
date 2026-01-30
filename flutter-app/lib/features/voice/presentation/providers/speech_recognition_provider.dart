import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/voice/data/datasources/speech_recognition_service.dart';
import 'package:lexilingo_app/features/voice/domain/entities/transcription.dart';

/// Speech Recognition Provider
/// Manages Web Speech Recognition state for Flutter Web
/// Falls back to server-side STT on other platforms
class SpeechRecognitionProvider extends ChangeNotifier {
  WebSpeechRecognition? _webSpeech;
  StreamSubscription? _resultSubscription;
  
  SpeechState _state = SpeechState.idle;
  String _transcript = '';
  String _interimTranscript = '';
  double _confidence = 0.0;
  String? _errorMessage;
  String _language = 'en-US';

  // Getters
  SpeechState get state => _state;
  String get transcript => _transcript;
  String get interimTranscript => _interimTranscript;
  String get fullTranscript => _transcript + _interimTranscript;
  double get confidence => _confidence;
  String? get errorMessage => _errorMessage;
  String get language => _language;

  bool get isIdle => _state == SpeechState.idle;
  bool get isListening => _state == SpeechState.listening;
  bool get isProcessing => _state == SpeechState.processing;
  bool get hasError => _state == SpeechState.error;

  /// Check if Web Speech API is available (web platform only)
  bool get isWebSpeechSupported => kIsWeb && WebSpeechRecognition.isSupported;

  /// Set recognition language
  void setLanguage(String lang) {
    _language = lang;
    notifyListeners();
  }

  /// Start listening with Web Speech API
  Future<void> startListening({String? language}) async {
    if (!kIsWeb) {
      _errorMessage = 'Web Speech Recognition is only available on web platform';
      _state = SpeechState.error;
      notifyListeners();
      return;
    }

    if (!WebSpeechRecognition.isSupported) {
      _errorMessage = 'Web Speech Recognition is not supported in this browser';
      _state = SpeechState.error;
      notifyListeners();
      return;
    }

    // Reset state
    _transcript = '';
    _interimTranscript = '';
    _errorMessage = null;
    _confidence = 0.0;

    // Initialize Web Speech
    _webSpeech?.dispose();
    _webSpeech = WebSpeechRecognition();

    final lang = language ?? _language;
    
    _state = SpeechState.listening;
    notifyListeners();

    try {
      final stream = _webSpeech!.startListening(language: lang);
      
      _resultSubscription?.cancel();
      _resultSubscription = stream.listen(
        (result) {
          if (result.isFinal) {
            _transcript += result.transcript;
            _interimTranscript = '';
            _confidence = result.confidence;
          } else {
            _interimTranscript = result.transcript;
          }
          notifyListeners();
        },
        onError: (error) {
          _errorMessage = error.toString();
          _state = SpeechState.error;
          notifyListeners();
        },
        onDone: () {
          if (_state == SpeechState.listening) {
            _state = SpeechState.idle;
            notifyListeners();
          }
        },
      );
    } catch (e) {
      _errorMessage = 'Failed to start speech recognition: $e';
      _state = SpeechState.error;
      notifyListeners();
    }
  }

  /// Stop listening
  void stopListening() {
    _webSpeech?.stopListening();
    _resultSubscription?.cancel();
    _interimTranscript = '';
    _state = SpeechState.idle;
    notifyListeners();
  }

  /// Get transcription result
  Transcription? getTranscription() {
    if (_transcript.isEmpty) return null;
    
    return Transcription(
      text: _transcript,
      language: _language,
      confidence: _confidence,
    );
  }

  /// Clear transcript
  void clearTranscript() {
    _transcript = '';
    _interimTranscript = '';
    _confidence = 0.0;
    _errorMessage = null;
    notifyListeners();
  }

  /// Reset state
  void reset() {
    stopListening();
    clearTranscript();
    _state = SpeechState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _resultSubscription?.cancel();
    _webSpeech?.dispose();
    super.dispose();
  }
}

enum SpeechState {
  idle,
  listening,
  processing,
  error,
}

/// Supported languages for speech recognition
class SpeechLanguages {
  static const Map<String, String> supported = {
    'en-US': 'English (US)',
    'en-GB': 'English (UK)',
    'vi-VN': 'Vietnamese',
    'fr-FR': 'French',
    'de-DE': 'German',
    'es-ES': 'Spanish',
    'ja-JP': 'Japanese',
    'ko-KR': 'Korean',
    'zh-CN': 'Chinese (Simplified)',
    'zh-TW': 'Chinese (Traditional)',
  };

  static String getName(String code) => supported[code] ?? code;
}
