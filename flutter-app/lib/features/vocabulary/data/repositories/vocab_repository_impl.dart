import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';

/// Vocabulary Repository Implementation
/// Implements vocab repository using local database
class VocabRepositoryImpl implements VocabRepository {
  final VocabLocalDataSource? localDataSource;

  VocabRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async {
    if (localDataSource == null) {
      return const Right([]); // Return empty if database is skipped
    }
    
    try {
      final words = await localDataSource!.getWords();
      return Right(words);
    } catch (e) {
      return Left(CacheFailure('Failed to get vocabulary words: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> addWord(VocabWord word) async {
    if (localDataSource == null) {
      return Left(CacheFailure('Cannot add word: Database is disabled'));
    }
    
    try {
      await localDataSource!.addWord(word);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to add vocabulary word: ${e.toString()}'));
    }
  }
}
