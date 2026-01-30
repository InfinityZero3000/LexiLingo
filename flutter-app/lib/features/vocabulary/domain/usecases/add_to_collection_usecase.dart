import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// UseCase: Add Vocabulary to Collection
/// Adds a vocabulary word to user's personal collection
class AddToCollectionUseCase 
    implements UseCase<UserVocabularyEntity, AddToCollectionParams> {
  final VocabularyRepository repository;

  AddToCollectionUseCase(this.repository);

  @override
  Future<Either<Failure, UserVocabularyEntity>> call(
    AddToCollectionParams params,
  ) async {
    return await repository.addToCollection(params.vocabularyId);
  }
}

class AddToCollectionParams extends Equatable {
  final String vocabularyId;

  const AddToCollectionParams({required this.vocabularyId});

  @override
  List<Object?> get props => [vocabularyId];
}
