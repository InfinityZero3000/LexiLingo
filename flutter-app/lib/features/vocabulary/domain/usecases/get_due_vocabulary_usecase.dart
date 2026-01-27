import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/user_vocabulary_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// UseCase: Get Due Vocabulary
/// Returns vocabulary items that need to be reviewed today
class GetDueVocabularyUseCase 
    implements UseCase<List<UserVocabularyEntity>, GetDueVocabularyParams> {
  final VocabularyRepository repository;

  GetDueVocabularyUseCase(this.repository);

  @override
  Future<Either<Failure, List<UserVocabularyEntity>>> call(
    GetDueVocabularyParams params,
  ) async {
    return await repository.getDueVocabulary(limit: params.limit);
  }
}

class GetDueVocabularyParams extends Equatable {
  final int limit;

  const GetDueVocabularyParams({this.limit = 20});

  @override
  List<Object?> get props => [limit];
}
