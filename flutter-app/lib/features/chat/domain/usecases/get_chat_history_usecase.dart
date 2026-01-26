import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/chat_message.dart';
import '../repositories/chat_repository.dart';

/// Use case for getting chat history (messages) for a session
class GetChatHistoryUseCase {
  final ChatRepository repository;

  GetChatHistoryUseCase(this.repository);

  /// Execute the use case
  /// Returns all messages for the given session
  Future<Either<Failure, List<ChatMessage>>> call(String sessionId) async {
    return await repository.getMessages(sessionId);
  }
}
