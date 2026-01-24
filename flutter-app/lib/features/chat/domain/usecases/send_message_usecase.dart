import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

class SendMessageParams {
  final String message;
  final String userId;
  final String sessionId;
  final AIModel model;
  final List<ChatMessage>? conversationHistory;

  SendMessageParams({
    required this.message,
    required this.userId,
    required this.sessionId,
    this.model = AIModel.gemini,
    this.conversationHistory,
  });
}

/// Sends a user message, gets AI response, and persists both.
///
/// This is the main domain usecase for the chat screen.
class SendMessageUseCase {
  final ChatRepository repository;

  SendMessageUseCase(this.repository);

  Future<Either<Failure, ChatMessage>> call(SendMessageParams params) async {
    final now = DateTime.now();

    // Persist user message (so history stays consistent across reloads).
    final userMessage = ChatMessage(
      id: _generateId(prefix: 'user'),
      sessionId: params.sessionId,
      content: params.message,
      role: MessageRole.user,
      timestamp: now,
      status: MessageStatus.sent,
    );

    final savedUser = await repository.saveMessage(userMessage);
    final savedUserOrFailure = savedUser.fold<Either<Failure, ChatMessage>>(
      (failure) => Left(failure),
      (value) => Right(value),
    );

    if (savedUserOrFailure.isLeft()) {
      return savedUserOrFailure;
    }

    // Request AI response.
    final aiResponseEither = await repository.getAIResponse(
      userId: params.userId,
      message: params.message,
      sessionId: params.sessionId,
      model: params.model,
      conversationHistory: params.conversationHistory,
    );

    return await aiResponseEither.fold(
      (failure) async => Left(failure),
      (aiText) async {
        final aiMessage = ChatMessage(
          id: _generateId(prefix: 'ai'),
          sessionId: params.sessionId,
          content: aiText,
          role: MessageRole.ai,
          timestamp: DateTime.now(),
          status: MessageStatus.sent,
        );

        return repository.saveMessage(aiMessage);
      },
    );
  }

  String _generateId({required String prefix}) {
    final t = DateTime.now();
    return '${prefix}_${t.millisecondsSinceEpoch}_${t.microsecond % 1000}';
  }
}
