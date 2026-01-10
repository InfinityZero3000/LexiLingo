import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/chat/domain/entities/message.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';

class GetChatHistoryUseCase implements UseCase<List<Message>, NoParams> {
  final ChatRepository repository;

  GetChatHistoryUseCase(this.repository);

  @override
  Future<List<Message>> call(NoParams params) async {
    return await repository.getChatHistory();
  }
}
