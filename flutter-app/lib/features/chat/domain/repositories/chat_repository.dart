import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/chat_message.dart';
import '../entities/chat_session.dart';
import '../entities/ai_analysis_result.dart';

/// Enum representing the AI model to use for chat
enum AIModel {
  /// Google Gemini model (cloud-based)
  gemini,

  /// Qwen model (local)
  qwen,

  /// GPT-4 model (cloud-based)
  gpt4,

  /// Claude model (cloud-based)
  claude,

  /// HuggingFace model (cloud-based, free tier)
  huggingface,

  /// Whisper model (speech-to-text)
  whisper,

  /// Piper model (text-to-speech)
  piper,

  /// HuBERT model (pronunciation analysis)
  hubert,

  /// Local fallback
  local,

  /// Cloud fallback
  cloud,
}

/// Extension methods for AIModel
extension AIModelExtension on AIModel {
  /// Get display name for the model
  String get displayName {
    switch (this) {
      case AIModel.gemini:
        return 'Gemini';
      case AIModel.qwen:
        return 'Qwen';
      case AIModel.gpt4:
        return 'GPT-4';
      case AIModel.claude:
        return 'Claude';
      case AIModel.huggingface:
        return 'HuggingFace';
      case AIModel.whisper:
        return 'Whisper';
      case AIModel.piper:
        return 'Piper';
      case AIModel.hubert:
        return 'HuBERT';
      case AIModel.local:
        return 'Local';
      case AIModel.cloud:
        return 'Cloud';
    }
  }

  /// Get short string representation
  String toShortString() {
    return toString().split('.').last;
  }

  /// Check if model is cloud-based
  bool get isCloudBased {
    return this == AIModel.gemini ||
        this == AIModel.gpt4 ||
        this == AIModel.claude ||
        this == AIModel.huggingface ||
        this == AIModel.cloud;
  }

  /// Check if model is for voice processing
  bool get isVoiceModel {
    return this == AIModel.whisper ||
        this == AIModel.piper ||
        this == AIModel.hubert;
  }

  /// Parse from string
  static AIModel fromString(String model) {
    switch (model.toLowerCase()) {
      case 'gemini':
        return AIModel.gemini;
      case 'qwen':
        return AIModel.qwen;
      case 'gpt4':
        return AIModel.gpt4;
      case 'claude':
        return AIModel.claude;
      case 'huggingface':
        return AIModel.huggingface;
      case 'whisper':
        return AIModel.whisper;
      case 'piper':
        return AIModel.piper;
      case 'hubert':
        return AIModel.hubert;
      case 'local':
        return AIModel.local;
      case 'cloud':
        return AIModel.cloud;
      default:
        return AIModel.gemini;
    }
  }
}

/// Abstract repository for chat functionality
/// Defines the contract between domain and data layers
abstract class ChatRepository {
  // ===== Session Management =====

  /// Create a new chat session for a user
  Future<Either<Failure, ChatSession>> createSession(String userId);

  /// Get all chat sessions for a user
  Future<Either<Failure, List<ChatSession>>> getSessions(String userId);

  /// Get a specific session by ID
  Future<Either<Failure, ChatSession>> getSessionById(String sessionId);

  /// Delete a chat session
  Future<Either<Failure, Unit>> deleteSession(String sessionId);

  /// Update session title
  Future<Either<Failure, Unit>> updateSessionTitle({
    required String sessionId,
    required String newTitle,
  });

  // ===== Message Management =====

  /// Save a chat message
  Future<Either<Failure, ChatMessage>> saveMessage(ChatMessage message);

  /// Get all messages for a session
  Future<Either<Failure, List<ChatMessage>>> getMessages(String sessionId);

  /// Update message status
  Future<Either<Failure, Unit>> updateMessageStatus({
    required String messageId,
    required MessageStatus status,
    String? error,
  });

  /// Delete a message
  Future<Either<Failure, Unit>> deleteMessage(String messageId);

  // ===== AI Operations =====

  /// Get AI response for a message
  Future<Either<Failure, String>> getAIResponse({
    required String userId,
    required String message,
    required String sessionId,
    required AIModel model,
    List<ChatMessage>? conversationHistory,
  });

  /// Analyze a message for grammar, vocabulary, etc.
  Future<Either<Failure, AIAnalysisResult>> analyzeMessage({
    required String message,
    required String messageId,
  });

  /// Watch messages in real-time (optional)
  Stream<List<ChatMessage>>? watchMessages(String sessionId);
}
