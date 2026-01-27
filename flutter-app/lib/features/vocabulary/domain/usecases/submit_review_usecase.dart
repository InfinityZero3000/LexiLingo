import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// UseCase: Submit Vocabulary Review
/// Submits a review result and updates SRS parameters
class SubmitReviewUseCase implements UseCase<ReviewResultEntity, SubmitReviewParams> {
  final VocabularyRepository repository;

  SubmitReviewUseCase(this.repository);

  @override
  Future<Either<Failure, ReviewResultEntity>> call(
    SubmitReviewParams params,
  ) async {
    return await repository.submitReview(
      params.userVocabularyId,
      params.quality,
      timeSpentMs: params.timeSpentMs,
    );
  }
}

class SubmitReviewParams extends Equatable {
  final String userVocabularyId;
  final ReviewQuality quality;
  final int? timeSpentMs;

  const SubmitReviewParams({
    required this.userVocabularyId,
    required this.quality,
    this.timeSpentMs,
  });

  @override
  List<Object?> get props => [userVocabularyId, quality, timeSpentMs];
}
