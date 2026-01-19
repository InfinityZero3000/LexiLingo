import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/chat_message_model.dart';
import '../../domain/repositories/chat_repository.dart';

class ChatRemoteDataSource {
  final String apiKey;
  late GenerativeModel _model;

  ChatRemoteDataSource({required this.apiKey}) {
    _model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
  }

  Future<String> sendMessage(String message) async {
    try {
      final content = [Content.text(message)];
      final response = await _model.generateContent(content);
      return response.text ?? "I didn't understand that.";
    } catch (e) {
      throw Exception('Failed to connect to AI');
    }
  }

  /// Get AI response with conversation history support
  Future<String> getAIResponse({
    required String message,
    required String sessionId,
    required AIModel model,
    List<ChatMessageModel>? conversationHistory,
  }) async {
    try {
      // Build conversation with history for context
      List<Content> contents = [];
      
      // Add conversation history if provided
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        for (var msg in conversationHistory) {
          contents.add(Content.text(msg.content));
        }
      }
      
      // Add current message
      contents.add(Content.text(message));
      
      final response = await _model.generateContent(contents);
      return response.text ?? "I didn't understand that.";
    } catch (e) {
      throw Exception('Failed to connect to AI: $e');
    }
  }
}
