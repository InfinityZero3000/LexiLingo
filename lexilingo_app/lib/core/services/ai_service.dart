import '../../features/chat/domain/repositories/chat_repository.dart';

/// Abstract base class for AI services
/// All AI model integrations must implement this interface
abstract class AIService {
  /// Get the name of this AI model
  String get modelName;

  /// Get the model type
  AIModel get modelType;

  /// Check if this service requires an API key
  bool get requiresApiKey;

  /// Cost per request (for tracking/monitoring)
  double get costPerRequest;

  /// Maximum tokens this model can handle
  int get maxTokens;

  /// Generate a response from the AI
  /// 
  /// [prompt] - The user's message
  /// [systemPrompt] - System instructions for the AI
  /// [conversationHistory] - Previous messages in the conversation
  /// [temperature] - Controls randomness (0.0 = deterministic, 1.0 = creative)
  /// 
  /// Returns the AI's text response
  Future<String> generateResponse({
    required String prompt,
    String? systemPrompt,
    List<Map<String, String>>? conversationHistory,
    double temperature = 0.7,
  });

  /// Test if the service is available and working
  /// Returns true if successful, false otherwise
  Future<bool> testConnection();

  /// Check if API key is configured
  bool isConfigured();
}

/// Exception thrown when AI service fails
class AIServiceException implements Exception {
  final String message;
  final AIModel? model;
  final String? details;

  AIServiceException(
    this.message, {
    this.model,
    this.details,
  });

  @override
  String toString() {
    if (details != null) {
      return 'AIServiceException: $message - $details';
    }
    return 'AIServiceException: $message';
  }
}
