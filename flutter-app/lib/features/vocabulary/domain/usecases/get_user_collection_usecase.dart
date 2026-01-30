import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// UseCase: Get User Vocabulary Collection
/// Returns user's vocabulary with optional status filter
class GetUserCollectionUseCase 
    implements UseCase<List<UserVocabularyEntity>, GetUserCollectionParams> {
  final VocabularyRepository repository;

  GetUserCollectionUseCase(this.repository);

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> call(
    GetUserCollectionParams params,
  ) async {
    return await repository.getUserCollection(
      status: params.status,
      limit: params.limit,
      offset: params.offset,
    );
  }
}

class GetUserCollectionParams extends Equatable {
  final VocabularyStatus? status;
  final int limit;
  final int offset;

  const GetUserCollectionParams({
    this.status,
    this.limit = 50,
    this.offset = 0,
  });

  @override
  List<Object?> get props => [status, limit, offset];
}
