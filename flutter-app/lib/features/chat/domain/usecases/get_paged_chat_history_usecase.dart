import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/chat_messages_page.dart';
import '../repositories/chat_repository.dart';

class GetPagedChatHistoryParams {
  final String sessionId;
  final int limit;
  final String? cursor;

  const GetPagedChatHistoryParams({
    required this.sessionId,
    required this.limit,
    this.cursor,
  });
}

/// Use case for cursor-based paged chat history retrieval.
class GetPagedChatHistoryUseCase {
  final ChatRepository repository;

  GetPagedChatHistoryUseCase(this.repository);

  Future<Either<Failure, ChatMessagesPage>> call(
    GetPagedChatHistoryParams params,
  ) async {
    return repository.getMessagesPaged(
      params.sessionId,
      limit: params.limit,
      cursor: params.cursor,
    );
  }
}
