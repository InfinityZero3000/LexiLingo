import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';

class VocabRepositoryImpl implements VocabRepository {
  final VocabLocalDataSource localDataSource;

  VocabRepositoryImpl({required this.localDataSource});

  @override
  Future<List<VocabWord>> getWords() async {
    return await localDataSource.getWords();
  }

  @override
  Future<void> addWord(VocabWord word) async {
    await localDataSource.addWord(word);
  }
}
