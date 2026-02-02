import 'package:google_generative_ai/google_generative_ai.dart';
import '../../../../../core/services/ai_service.dart';
import '../../../../../core/utils/app_logger.dart';
import '../../../domain/repositories/chat_repository.dart';

/// Google Gemini AI Service implementation
/// Primary AI service for the application
class GeminiService implements AIService {
  final String apiKey;
  late final GenerativeModel _model;
  
  static const String _defaultModelName = 'gemini-2.5-pro';

  GeminiService({
    required this.apiKey,
    String? modelName,
  }) {
    _model = GenerativeModel(
      model: modelName ?? _defaultModelName,
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 1024,
      ),
      safetySettings: [
        SafetySetting(HarmCategory.harassment, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.hateSpeech, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.sexuallyExplicit, HarmBlockThreshold.medium),
        SafetySetting(HarmCategory.dangerousContent, HarmBlockThreshold.medium),
      ],
    );
  }

  @override
  String get modelName => 'Google Gemini';

  @override
  AIModel get modelType => AIModel.gemini;

  @override
  bool get requiresApiKey => true;

  @override
  double get costPerRequest => 0.0; // Free tier available

  @override
  int get maxTokens => 8192;

  @override
  bool isConfigured() {
    return apiKey.isNotEmpty;
  }

  @override
  Future<String> generateResponse({
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
    double temperature = 0.7,
  }) async {
    try {
      // Build the full prompt
      final fullPrompt = _buildPrompt(
        userMessage: prompt,
        systemPrompt: systemPrompt,
        history: conversationHistory,
      );

      // Generate content
      final response = await _model.generateContent([
        Content.text(fullPrompt),
      ]);

      // Extract text from response
      final text = response.text;
      if (text == null || text.isEmpty) {
        throw AIServiceException(
          'Gemini returned empty response',
          model: AIModel.gemini,
        );
      }

      return text.trim();
    } on GenerativeAIException catch (e) {
      throw AIServiceException(
        'Gemini API error',
        model: AIModel.gemini,
        details: e.message,
      );
    } catch (e) {
      throw AIServiceException(
        'Failed to generate response',
        model: AIModel.gemini,
        details: e.toString(),
      );
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      final response = await _model.generateContent([
        Content.text('Hello'),
      ]);
      return response.text != null && response.text!.isNotEmpty;
    } catch (e) {
      print('Gemini connection test failed: $e');
      return false;
    }
  }

  /// Build a formatted prompt for Gemini
  /// Includes system instructions, conversation history, and user message
  String _buildPrompt({
    required String userMessage,
    String? systemPrompt,
    List<Map<String, String>>? history,
  }) {
    final buffer = StringBuffer();

    // Add system prompt (instructions for AI behavior)
    final effectiveSystemPrompt = systemPrompt ?? _getDefaultSystemPrompt();
    buffer.writeln('System Instructions:');
    buffer.writeln(effectiveSystemPrompt);
    buffer.writeln();

    // Add conversation history if available
    if (history != null && history.isNotEmpty) {
      buffer.writeln('Conversation History:');
      for (final message in history) {
        final role = message['role'] ?? 'unknown';
        final content = message['content'] ?? '';
        if (role == 'user') {
          buffer.writeln('User: $content');
        } else if (role == 'ai') {
          buffer.writeln('AI: $content');
        }
      }
      buffer.writeln();
    }

    // Add current user message
    buffer.writeln('User: $userMessage');
    buffer.writeln();
    buffer.write('AI:');

    return buffer.toString();
  }

  /// Get default system prompt for English learning
  String _getDefaultSystemPrompt() {
    return '''
You are an English learning AI assistant for A2-B1 level learners.
Your role is to:
- Help users practice English conversation
- Correct grammar mistakes politely and constructively
- Explain difficult vocabulary when needed
- Keep your responses appropriate for A2-B1 level (not too complex)
- Be encouraging and supportive
- Use clear, simple English
- When correcting errors, show the correct form and briefly explain why

Important guidelines:
- Don't be overly critical
- Focus on communication, not perfection
- Encourage the user to keep practicing
- If the user makes a mistake, acknowledge what they said, gently correct it, and continue the conversation
''';
  }
}
