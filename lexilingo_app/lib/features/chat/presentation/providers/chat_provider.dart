import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/chat/domain/entities/message.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';

class ChatProvider extends ChangeNotifier {
  final ChatRepository repository;
  List<Message> _messages = [];
  bool _isLoading = false;

  ChatProvider({required this.repository}) {
    _loadHistory();
  }

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;

  Future<void> _loadHistory() async {
    _messages = await repository.getChatHistory();
    notifyListeners();
  }

  Future<void> sendMessage(String content) async {
    if (content.isEmpty) return;

    final userMsg = Message(content: content, isUser: true, timestamp: DateTime.now());
    _messages.add(userMsg);
    _isLoading = true;
    notifyListeners();

    await repository.saveMessage(userMsg);

    try {
      final aiResponseText = await repository.sendMessageToAI(content);
      final aiMsg = Message(content: aiResponseText, isUser: false, timestamp: DateTime.now());
      
      _messages.add(aiMsg);
      await repository.saveMessage(aiMsg);
    } catch (e) {
      _messages.add(Message(content: "Error: Could not get response.", isUser: false, timestamp: DateTime.now()));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
