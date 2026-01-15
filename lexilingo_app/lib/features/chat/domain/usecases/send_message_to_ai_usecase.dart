import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_message.dart';

class SendMessageParams {
  final String message;
  final String sessionId;
  final AIModel model;
  final List<ChatMessage>? conversationHistory;

  SendMessageParams({
    required this.message,
    required this.sessionId,
    this.model = AIModel.gemini,
    this.conversationHistory,
  });
}

class SendMessageToAIUseCase implements UseCase<Either<Failure, String>, SendMessageParams> {
  final ChatRepository repository;

  SendMessageToAIUseCase(this.repository);

  @override
  Future<Either<Failure, String>> call(SendMessageParams params) async {
    return await repository.getAIResponse(
      message: params.message,
      sessionId: params.sessionId,
      model: params.model,
      conversationHistory: params.conversationHistory,
    );
  }
}
