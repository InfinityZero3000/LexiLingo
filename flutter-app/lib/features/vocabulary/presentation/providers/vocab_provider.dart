import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';

/// Result from the free Dictionary API lookup.
class DictionaryLookupResult {
  final String word;
  final String? pronunciation; // IPA
  final String? audioUrl;
  final String? definition;
  final String? example;
  final String? partOfSpeech;
  final bool found;

  const DictionaryLookupResult({
    required this.word,
    this.pronunciation,
    this.audioUrl,
    this.definition,
    this.example,
    this.partOfSpeech,
    required this.found,
  });
}

class VocabProvider extends ChangeNotifier {
  final GetWordsUseCase getWordsUseCase;
  final AddWordUseCase addWordUseCase;
  List<VocabWord> _words = [];
  String? _errorMessage;
  bool _isLoading = false;

  // Dictionary lookup state
  DictionaryLookupResult? _lookupResult;
  bool _isLookingUp = false;

  VocabProvider({required this.getWordsUseCase, required this.addWordUseCase}) {
    loadWords();
  }

  List<VocabWord> get words => _words;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  DictionaryLookupResult? get lookupResult => _lookupResult;
  bool get isLookingUp => _isLookingUp;

  Future<void> loadWords() async {
    _isLoading = true;
    notifyListeners();

    final result = await getWordsUseCase(NoParams());
    result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
        _words = [];
      },
      (words) {
        _words = words;
        _errorMessage = null;
      },
    );
    _isLoading = false;
    notifyListeners();
  }

  /// Look up a word in the free Dictionary API.
  /// Fills [lookupResult] with pronunciation, definition, example, partOfSpeech.
  Future<DictionaryLookupResult> lookupWord(String word) async {
    _isLookingUp = true;
    _lookupResult = null;
    notifyListeners();

    final trimmed = word.trim().toLowerCase();
    DictionaryLookupResult result;
    try {
      final uri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/en/$trimmed',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final entry = data[0] as Map<String, dynamic>;

        // Phonetics
        String? ipa;
        String? audio;
        final phonetics = entry['phonetics'] as List<dynamic>? ?? [];
        for (final p in phonetics) {
          final pm = p as Map<String, dynamic>;
          ipa ??= pm['text'] as String?;
          if (audio == null) {
            final a = pm['audio'] as String?;
            if (a != null && a.isNotEmpty) audio = a;
          }
          if (ipa != null && audio != null) break;
        }

        // Meanings
        String? definition;
        String? example;
        String? pos;
        final meanings = entry['meanings'] as List<dynamic>? ?? [];
        if (meanings.isNotEmpty) {
          final meaning = meanings[0] as Map<String, dynamic>;
          pos = meaning['partOfSpeech'] as String?;
          final defs = meaning['definitions'] as List<dynamic>? ?? [];
          if (defs.isNotEmpty) {
            final def = defs[0] as Map<String, dynamic>;
            definition = def['definition'] as String?;
            example = def['example'] as String?;
          }
        }

        result = DictionaryLookupResult(
          word: word,
          pronunciation: ipa,
          audioUrl: audio,
          definition: definition,
          example: example,
          partOfSpeech: pos,
          found: true,
        );
      } else {
        result = DictionaryLookupResult(word: word, found: false);
      }
    } catch (_) {
      result = DictionaryLookupResult(word: word, found: false);
    }

    _lookupResult = result;
    _isLookingUp = false;
    notifyListeners();
    return result;
  }

  void clearLookup() {
    _lookupResult = null;
    notifyListeners();
  }

  Future<bool> addWord(
    String word,
    String definition, {
    String? pronunciation,
    String? audioUrl,
    String? example,
    String? partOfSpeech,
  }) async {
    final result = await addWordUseCase(
      AddWordParams(
        word: word,
        definition: definition,
        pronunciation: pronunciation,
        audioUrl: audioUrl,
        example: example,
        partOfSpeech: partOfSpeech,
      ),
    );
    bool success = false;
    result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
      },
      (_) {
        _errorMessage = null;
        success = true;
      },
    );
    await loadWords();
    return success;
  }

  String _getFailureMessage(Failure failure) {
    if (failure is ServerFailure) {
      return failure.message;
    } else if (failure is NetworkFailure) {
      return 'Network error. Please check your internet connection.';
    } else if (failure is CacheFailure) {
      return 'Local storage error.';
    } else {
      return 'An error occurred. Please try again.';
    }
  }
}
