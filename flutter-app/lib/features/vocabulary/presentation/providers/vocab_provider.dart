import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';

class VocabProvider extends ChangeNotifier {
  final GetWordsUseCase getWordsUseCase;
  final AddWordUseCase addWordUseCase;
  List<VocabWord> _words = [];

  VocabProvider({
    required this.getWordsUseCase,
    required this.addWordUseCase,
  }) {
    loadWords();
  }

  List<VocabWord> get words => _words;

  Future<void> loadWords() async {
    _words = await getWordsUseCase(NoParams());
    notifyListeners();
  }

  Future<void> addWord(String word, String definition) async {
    await addWordUseCase(AddWordParams(word: word, definition: definition));
    await loadWords();
  }
}
