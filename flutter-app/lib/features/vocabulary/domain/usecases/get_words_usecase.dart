import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';

class GetWordsUseCase implements UseCase<List<VocabWord>, NoParams> {
  final VocabRepository repository;

  GetWordsUseCase(this.repository);

  @override
  Future<List<VocabWord>> call(NoParams params) async {
    return await repository.getWords();
  }
}
