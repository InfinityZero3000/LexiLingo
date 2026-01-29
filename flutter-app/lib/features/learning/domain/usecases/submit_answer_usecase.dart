import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/data/models/answer_response_model.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

/// Submit Answer Use Case
/// Submits an answer for a question in the current lesson attempt
class SubmitAnswerUseCase implements UseCase<AnswerResponseModel, SubmitAnswerParams> {
  final LearningRepository _repository;

  SubmitAnswerUseCase({required LearningRepository repository}) : _repository = repository;

  @override
  Future<Either<Failure, AnswerResponseModel>> call(SubmitAnswerParams params) {
    return _repository.submitAnswer(
      attemptId: params.attemptId,
      questionId: params.questionId,
      questionType: params.questionType,
      userAnswer: params.userAnswer,
      timeSpentMs: params.timeSpentMs,
      hintUsed: params.hintUsed,
      confidenceScore: params.confidenceScore,
    );
  }
}

/// Parameters for SubmitAnswerUseCase
class SubmitAnswerParams {
  final String attemptId;
  final String questionId;
  final String questionType;
  final dynamic userAnswer;
  final int timeSpentMs;
  final bool hintUsed;
  final double? confidenceScore;

  SubmitAnswerParams({
    required this.attemptId,
    required this.questionId,
    required this.questionType,
    required this.userAnswer,
    required this.timeSpentMs,
    this.hintUsed = false,
    this.confidenceScore,
  });
}
