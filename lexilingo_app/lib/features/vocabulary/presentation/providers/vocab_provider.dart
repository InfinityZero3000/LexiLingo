import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';

class VocabProvider extends ChangeNotifier {
  final VocabRepository repository;
  List<VocabWord> _words = [];

  VocabProvider({required this.repository}) {
    loadWords();
  }

  List<VocabWord> get words => _words;

  Future<void> loadWords() async {
    _words = await repository.getWords();
    notifyListeners();
  }

  Future<void> addWord(String word, String definition) async {
    final newWord = VocabWord(word: word, definition: definition);
    await repository.addWord(newWord);
    await loadWords();
  }
}
