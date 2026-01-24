import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/chat_session.dart';
import '../repositories/chat_repository.dart';

/// Use case for getting all chat sessions for a user
class GetSessionsUseCase {
  final ChatRepository repository;

  GetSessionsUseCase(this.repository);

  /// Execute the use case
  /// Returns all sessions for the given user, ordered by most recent
  Future<Either<Failure, List<ChatSession>>> call(String userId) async {
    return await repository.getSessions(userId);
  }
}
