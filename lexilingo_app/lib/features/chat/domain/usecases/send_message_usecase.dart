import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

/// Use case for sending a message and getting AI response
/// This orchestrates the entire message sending flow
class SendMessageUseCase {
  final ChatRepository repository;

  SendMessageUseCase(this.repository);

  /// Execute the use case
  /// Returns the AI's response message or a failure
  Future<Either<Failure, ChatMessage>> call(SendMessageParams params) async {
    // 1. Save user message with 'sending' status
    final userMessage = ChatMessage(
      id: _generateId(),
      sessionId: params.sessionId,
      content: params.message,
      role: MessageRole.user,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    final saveResult = await repository.saveMessage(userMessage);
    if (saveResult.isLeft()) {
      return saveResult;
    }

    // 2. Get AI response
    final aiResponseResult = await repository.getAIResponse(
      message: params.message,
      sessionId: params.sessionId,
      model: params.model,
      conversationHistory: params.conversationHistory,
    );

    return aiResponseResult.fold(
      // On failure: update user message status to error
      (failure) async {
        await repository.updateMessageStatus(
          messageId: userMessage.id,
          status: MessageStatus.error,
          error: failure.message,
        );
        return Left(failure);
      },
      // On success: save AI message and update user message
      (aiResponse) async {
        // Update user message to 'sent'
        await repository.updateMessageStatus(
          messageId: userMessage.id,
          status: MessageStatus.sent,
        );

        // Create and save AI message
        final aiMessage = ChatMessage(
          id: _generateId(),
          sessionId: params.sessionId,
          content: aiResponse,
          role: MessageRole.ai,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        );

        final aiSaveResult = await repository.saveMessage(aiMessage);
        return aiSaveResult;
      },
    );
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        (DateTime.now().microsecond % 1000).toString();
  }
}

/// Parameters for SendMessageUseCase
class SendMessageParams {
  final String sessionId;
  final String message;
  final AIModel model;
  final List<ChatMessage>? conversationHistory;

  SendMessageParams({
    required this.sessionId,
    required this.message,
    required this.model,
    this.conversationHistory,
  });
}
