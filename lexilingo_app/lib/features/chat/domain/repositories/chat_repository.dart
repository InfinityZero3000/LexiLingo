import 'package:dartz/dartz.dart';
import '../entities/chat_message.dart';
import '../entities/chat_session.dart';
import '../entities/ai_analysis_result.dart';
import '../../../../core/error/failures.dart';

/// Repository interface for chat feature
/// This defines the contract that the data layer must implement
/// Following Clean Architecture principles - domain doesn't depend on data
abstract class ChatRepository {
  // ===== Session Management =====
  
  /// Create a new chat session for the given user
  /// Returns the created session or a failure
  Future<Either<Failure, ChatSession>> createSession(String userId);

  /// Get all chat sessions for a specific user
  /// Ordered by most recent first
  Future<Either<Failure, List<ChatSession>>> getSessions(String userId);

  /// Get a specific session by ID, including its messages
  Future<Either<Failure, ChatSession>> getSessionById(String sessionId);

  /// Delete a chat session and all its messages
  Future<Either<Failure, Unit>> deleteSession(String sessionId);

  /// Update session title
  Future<Either<Failure, Unit>> updateSessionTitle({
    required String sessionId,
    required String newTitle,
  });

  // ===== Message Management =====

  /// Save a message to the database
  /// Used for both user and AI messages
  Future<Either<Failure, ChatMessage>> saveMessage(ChatMessage message);

  /// Get all messages for a specific session
  /// Ordered by timestamp (oldest first)
  Future<Either<Failure, List<ChatMessage>>> getMessages(String sessionId);

  /// Update message status (sending -> sent -> error)
  Future<Either<Failure, Unit>> updateMessageStatus({
    required String messageId,
    required MessageStatus status,
    String? error,
  });

  /// Delete a specific message
  Future<Either<Failure, Unit>> deleteMessage(String messageId);

  // ===== AI Operations =====

  /// Get AI response for a user message
  /// This calls the remote AI service
  /// Returns the AI's text response
  Future<Either<Failure, String>> getAIResponse({
    required String message,
    required String sessionId,
    required AIModel model,
    List<ChatMessage>? conversationHistory,
  });

  /// Analyze a message for grammar, fluency, vocabulary
  /// This is a future feature - will use AI models for analysis
  /// For now, this can return a simple placeholder
  Future<Either<Failure, AIAnalysisResult>> analyzeMessage({
    required String message,
    required String messageId,
  });

  /// Stream of messages for a session (for real-time updates)
  /// Optional feature for future implementation
  Stream<List<ChatMessage>>? watchMessages(String sessionId);
}

/// Enum representing different AI models that can be used
enum AIModel {
  /// Google Gemini API (Primary model)
  gemini,

  /// OpenAI GPT models (Fallback)
  openai,

  /// HuggingFace inference API (Free models for testing)
  huggingface,

  /// Local on-device models (Future feature)
  local,
}

/// Extension for AIModel enum
extension AIModelExtension on AIModel {
  /// Get display name for the model
  String get displayName {
    switch (this) {
      case AIModel.gemini:
        return 'Google Gemini';
      case AIModel.openai:
        return 'OpenAI GPT';
      case AIModel.huggingface:
        return 'HuggingFace';
      case AIModel.local:
        return 'Local Model';
    }
  }

  /// Get model identifier string
  String toShortString() {
    return toString().split('.').last;
  }

  /// Create AIModel from string
  static AIModel fromString(String model) {
    switch (model.toLowerCase()) {
      case 'gemini':
        return AIModel.gemini;
      case 'openai':
        return AIModel.openai;
      case 'huggingface':
        return AIModel.huggingface;
      case 'local':
        return AIModel.local;
      default:
        return AIModel.gemini; // Default to Gemini
    }
  }

  /// Check if model requires API key
  bool get requiresApiKey {
    switch (this) {
      case AIModel.gemini:
      case AIModel.openai:
      case AIModel.huggingface:
        return true;
      case AIModel.local:
        return false;
    }
  }

  /// Check if model is available offline
  bool get isOffline {
    return this == AIModel.local;
  }
}
