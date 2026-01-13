import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../../../core/services/ai_service.dart';
import '../../../../domain/repositories/chat_repository.dart';

/// HuggingFace Inference API Service
/// Provides access to free AI models via HuggingFace API
class HuggingFaceService implements AIService {
  final http.Client httpClient;
  final String apiKey;
  final String modelId;

  static const String _baseUrl = 'https://api-inference.huggingface.co/models';
  
  // Free models available for testing
  static const String defaultModelId = 'microsoft/DialoGPT-medium';
  static const String alternativeModel1 = 'facebook/blenderbot-400M-distill';
  static const String alternativeModel2 = 'HuggingFaceH4/zephyr-7b-beta';

  HuggingFaceService({
    required this.httpClient,
    required this.apiKey,
    String? modelId,
  }) : modelId = modelId ?? defaultModelId;

  @override
  String get modelName => 'HuggingFace ($modelId)';

  @override
  AIModel get modelType => AIModel.huggingface;

  @override
  bool get requiresApiKey => true;

  @override
  double get costPerRequest => 0.0; // Free tier

  @override
  int get maxTokens => 512; // Varies by model

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
      // Build input text
      final inputText = _buildInput(
        userMessage: prompt,
        systemPrompt: systemPrompt,
        history: conversationHistory,
      );

      final url = Uri.parse('$_baseUrl/$modelId');
      
      final response = await httpClient.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'inputs': inputText,
          'parameters': {
            'temperature': temperature,
            'max_length': 150,
            'max_new_tokens': 100,
            'return_full_text': false,
            'do_sample': true,
          },
          'options': {
            'wait_for_model': true,
            'use_cache': false,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Handle different response formats
        if (data is List && data.isNotEmpty) {
          final firstResult = data[0];
          if (firstResult is Map<String, dynamic>) {
            return _extractText(firstResult);
          }
        } else if (data is Map<String, dynamic>) {
          return _extractText(data);
        }
        
        throw AIServiceException(
          'Unexpected response format from HuggingFace',
          model: AIModel.huggingface,
          details: 'Response: ${response.body}',
        );
      } else if (response.statusCode == 503) {
        // Model is loading
        throw AIServiceException(
          'Model is loading, please try again in a few seconds',
          model: AIModel.huggingface,
          details: 'Status: 503',
        );
      } else if (response.statusCode == 429) {
        // Rate limited
        throw AIServiceException(
          'Rate limit exceeded, please try again later',
          model: AIModel.huggingface,
          details: 'Status: 429',
        );
      } else {
        // Other error
        throw AIServiceException(
          'HuggingFace API error',
          model: AIModel.huggingface,
          details: 'Status: ${response.statusCode}, Body: ${response.body}',
        );
      }
    } on AIServiceException {
      rethrow;
    } catch (e) {
      throw AIServiceException(
        'Failed to generate response from HuggingFace',
        model: AIModel.huggingface,
        details: e.toString(),
      );
    }
  }

  @override
  Future<bool> testConnection() async {
    try {
      final response = await generateResponse(
        prompt: 'Hello',
        temperature: 0.5,
      );
      return response.isNotEmpty;
    } catch (e) {
      print('HuggingFace connection test failed: $e');
      return false;
    }
  }

  /// Extract text from HuggingFace response
  String _extractText(Map<String, dynamic> data) {
    // Try common response fields
    if (data.containsKey('generated_text')) {
      return data['generated_text'].toString().trim();
    }
    if (data.containsKey('text')) {
      return data['text'].toString().trim();
    }
    if (data.containsKey('generated')) {
      return data['generated'].toString().trim();
    }
    if (data.containsKey('response')) {
      return data['response'].toString().trim();
    }
    
    throw AIServiceException(
      'Could not extract text from response',
      model: AIModel.huggingface,
      details: 'Data keys: ${data.keys.join(", ")}',
    );
  }

  /// Build input for HuggingFace models
  String _buildInput({
    required String userMessage,
    String? systemPrompt,
    List<Map<String, String>>? history,
  }) {
    final buffer = StringBuffer();

    // Some models work better with system prompts, some don't
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln(systemPrompt);
      buffer.writeln();
    }

    // Add recent history (limit to last 3 exchanges to stay within token limit)
    if (history != null && history.isNotEmpty) {
      final recentHistory = history.length > 6 
          ? history.sublist(history.length - 6) 
          : history;
      
      for (final message in recentHistory) {
        final role = message['role'];
        final content = message['content'];
        if (role == 'user') {
          buffer.writeln('User: $content');
        } else if (role == 'ai') {
          buffer.writeln('AI: $content');
        }
      }
    }

    // Add current message
    buffer.write('User: $userMessage\nAI:');

    return buffer.toString();
  }
}
