import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/chat/domain/entities/message.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';

class SaveMessageParams {
  final Message message;

  SaveMessageParams({required this.message});
}

class SaveMessageUseCase implements UseCase<void, SaveMessageParams> {
  final ChatRepository repository;

  SaveMessageUseCase(this.repository);

  @override
  Future<void> call(SaveMessageParams params) async {
    return await repository.saveMessage(params.message);
  }
}
