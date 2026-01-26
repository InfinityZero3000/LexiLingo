import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_message.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';

class SaveMessageParams {
  final ChatMessage message;

  SaveMessageParams({required this.message});
}

class SaveMessageUseCase implements UseCase<ChatMessage, SaveMessageParams> {
  final ChatRepository repository;

  SaveMessageUseCase(this.repository);

  @override
  Future<Either<Failure, ChatMessage>> call(SaveMessageParams params) async {
    return await repository.saveMessage(params.message);
  }
}
