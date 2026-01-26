import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/chat_session.dart';
import '../repositories/chat_repository.dart';

/// Use case for creating a new chat session
class CreateSessionUseCase {
  final ChatRepository repository;

  CreateSessionUseCase(this.repository);

  /// Execute the use case
  /// Creates a new chat session for the given user
  Future<Either<Failure, ChatSession>> call(String userId) async {
    return await repository.createSession(userId);
  }
}
