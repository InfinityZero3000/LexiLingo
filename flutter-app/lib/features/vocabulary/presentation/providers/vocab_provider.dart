import 'package:flutter/material.dart';
import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';

class VocabProvider extends ChangeNotifier {
  final GetWordsUseCase getWordsUseCase;
  final AddWordUseCase addWordUseCase;
  List<VocabWord> _words = [];
  String? _errorMessage;

  VocabProvider({
    required this.getWordsUseCase,
    required this.addWordUseCase,
  }) {
    loadWords();
  }

  List<VocabWord> get words => _words;
  String? get errorMessage => _errorMessage;

  Future<void> loadWords() async {
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
    notifyListeners();
  }

  Future<void> addWord(String word, String definition) async {
    final result = await addWordUseCase(AddWordParams(word: word, definition: definition));
    result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
      },
      (_) {
        _errorMessage = null;
      },
    );
    await loadWords();
  }

  String _getFailureMessage(Failure failure) {
    if (failure is ServerFailure) {
      return failure.message ?? 'Server error. Please try again later.';
    } else if (failure is NetworkFailure) {
      return 'Network error. Please check your internet connection.';
    } else if (failure is CacheFailure) {
      return 'Local storage error.';
    } else {
      return 'An error occurred. Please try again.';
    }
  }
}
