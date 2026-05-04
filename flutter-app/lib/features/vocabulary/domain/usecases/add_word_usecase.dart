import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';

class AddWordParams {
  final String word;
  final String definition;
  final String? pronunciation;
  final String? audioUrl;
  final String? example;
  final String? partOfSpeech;

  AddWordParams({
    required this.word,
    required this.definition,
    this.pronunciation,
    this.audioUrl,
    this.example,
    this.partOfSpeech,
  });
}

class AddWordUseCase implements UseCase<void, AddWordParams> {
  final VocabRepository repository;

  AddWordUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(AddWordParams params) async {
    final newWord = VocabWord(
      word: params.word,
      definition: params.definition,
      pronunciation: params.pronunciation,
      audioUrl: params.audioUrl,
      example: params.example,
      partOfSpeech: params.partOfSpeech,
    );
    return await repository.addWord(newWord);
  }
}
