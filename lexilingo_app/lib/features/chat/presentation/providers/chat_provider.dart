import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/chat/domain/entities/message.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/get_chat_history_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/save_message_usecase.dart';
import 'package:lexilingo_app/features/chat/domain/usecases/send_message_to_ai_usecase.dart';

class ChatProvider extends ChangeNotifier {
  final SendMessageToAIUseCase sendMessageToAIUseCase;
  final SaveMessageUseCase saveMessageUseCase;
  final GetChatHistoryUseCase getChatHistoryUseCase;
  List<Message> _messages = [];
  bool _isLoading = false;

  ChatProvider({
    required this.sendMessageToAIUseCase,
    required this.saveMessageUseCase,
    required this.getChatHistoryUseCase,
  }) {
    _loadHistory();
  }

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;

  Future<void> _loadHistory() async {
    _messages = await getChatHistoryUseCase(NoParams());
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (content.isEmpty) return;

    final userMsg = Message(content: content, isUser: true, timestamp: DateTime.now());
    _messages.add(userMsg);
    _isLoading = true;
    notifyListeners();

    await saveMessageUseCase(SaveMessageParams(message: userMsg));

    try {
      final aiResponseText = await sendMessageToAIUseCase(SendMessageParams(message: content));
      final aiMsg = Message(content: aiResponseText, isUser: false, timestamp: DateTime.now());
      
      _messages.add(aiMsg);
      await saveMessageUseCase(SaveMessageParams(message: aiMsg));
    } catch (e) {
      _messages.add(Message(content: "Error: Could not get response.", isUser: false, timestamp: DateTime.now()));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
