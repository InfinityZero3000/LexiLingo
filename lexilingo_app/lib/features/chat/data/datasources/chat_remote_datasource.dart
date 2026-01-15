import '../../../../core/error/exceptions.dart';
import '../../../../core/services/ai_service.dart';
import '../models/chat_message_model.dart';
import 'ai/ai_service_manager.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/entities/chat_message.dart'; // For MessageRoleExtension

/// Abstract interface for remote chat data source
abstract class ChatRemoteDataSource {
  /// Get AI response for a user message
  Future<String> getAIResponse({
    required String message,
    required String sessionId,
    required AIModel model,
    List<ChatMessageModel>? conversationHistory,
  });
}

/// Implementation of remote data source using AI services
class ChatRemoteDataSourceImpl implements ChatRemoteDataSource {
  final AIServiceManager aiServiceManager;

  ChatRemoteDataSourceImpl({
    required this.aiServiceManager,
  });

  @override
  Future<String> getAIResponse({
    required String message,
    required String sessionId,
    required AIModel model,
    List<ChatMessageModel>? conversationHistory,
  }) async {
    try {
      // Build system prompt for English learning
      final systemPrompt = _buildSystemPrompt();

      // Format conversation history
      final formattedHistory = _formatConversationHistory(conversationHistory);

      // Get response from AI service manager (with automatic fallback)
      final response = await aiServiceManager.getResponse(
        prompt: message,
        systemPrompt: systemPrompt,
        conversationHistory: formattedHistory,
        preferredModel: model,
        temperature: 0.7,
      );

      return response;
    } on AIServiceException catch (e) {
      throw ServerException(
        'AI Service Error: ${e.message}${e.details != null ? " - ${e.details}" : ""}',
      );
    } catch (e) {
      throw ServerException('Failed to get AI response: $e');
    }
  }

  /// Build system prompt for English learning context
  String _buildSystemPrompt() {
    return '''
You are an English learning AI assistant helping A2-B1 level learners.

Your responsibilities:
1. Engage in natural conversation in English
2. Gently correct grammar mistakes when you notice them
3. Explain difficult vocabulary if the user seems confused
4. Keep responses at an appropriate level (not too complex)
5. Be encouraging and supportive
6. Focus on helping users improve their English skills

Guidelines:
- Use clear, simple English
- Don't overwhelm users with too many corrections at once
- Prioritize communication over perfection
- When correcting, show the correct form and briefly explain
- Be friendly and patient
- Encourage users to continue practicing

Example correction format:
User: "I go to school yesterday"
AI: "I understand! You went to school yesterday. We use 'went' (past tense) for past actions. How was your day at school?"
''';
  }

  /// Format conversation history for AI
  /// Converts ChatMessageModel list to simple map format
  List<Map<String, String>> _formatConversationHistory(
    List<ChatMessageModel>? history,
  ) {
    if (history == null || history.isEmpty) {
      return [];
    }

    // Only include recent messages to stay within token limits
    // Take last 10 messages (5 exchanges)
    final recentHistory = history.length > 10 
        ? history.sublist(history.length - 10) 
        : history;

    return recentHistory.map((msg) {
      return {
        'role': msg.role.toShortString(),
        'content': msg.content,
      };
    }).toList();
  }
}
