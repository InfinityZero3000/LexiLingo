import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';

abstract class VocabRepository {
  Future<List<VocabWord>> getWords();
  Future<void> addWord(VocabWord word);
}
