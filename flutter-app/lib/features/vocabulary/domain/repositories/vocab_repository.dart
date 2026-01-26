import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';

abstract class VocabRepository {
  Future<Either<Failure, List<VocabWord>>> getWords();
  Future<Either<Failure, void>> addWord(VocabWord word);
}
