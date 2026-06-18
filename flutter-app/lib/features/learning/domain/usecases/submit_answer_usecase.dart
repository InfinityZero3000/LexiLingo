import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/learning/domain/entities/answer_response.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';

class SubmitAnswerUseCase
    implements UseCase<AnswerResponse, SubmitAnswerParams> {
  final LearningRepository _repository;

  SubmitAnswerUseCase({required LearningRepository repository})
    : _repository = repository;

  @override
  Future<Either<Failure, AnswerResponse>> call(SubmitAnswerParams params) {
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
