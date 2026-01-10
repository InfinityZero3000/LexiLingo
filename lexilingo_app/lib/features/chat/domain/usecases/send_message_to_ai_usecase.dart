import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';

class SendMessageParams {
  final String message;

  SendMessageParams({required this.message});
}

class SendMessageToAIUseCase implements UseCase<String, SendMessageParams> {
  final ChatRepository repository;

  SendMessageToAIUseCase(this.repository);

  @override
  Future<String> call(SendMessageParams params) async {
    return await repository.sendMessageToAI(params.message);
  }
}
