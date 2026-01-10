import 'package:lexilingo_app/features/chat/domain/entities/message.dart';

abstract class ChatRepository {
  Future<String> sendMessageToAI(String message);
  Future<void> saveMessage(Message message);
  Future<List<Message>> getChatHistory();
}
