import 'package:dartz/dartz.dart';

import '../../../../core/error/failures.dart';
import '../entities/ai_analysis_result.dart';
import '../entities/chat_message.dart';
import '../entities/chat_session.dart';

/// Supported AI models for chat/tutor.
///
/// Keep this enum stable because it is used across multiple layers
/// (presentation/domain/data) as a routing key.
enum AIModel {
  gemini,
  huggingface,
}

/// Contract for chat feature.
///
/// - Domain layer depends on this interface only.
/// - Data layer implements it (local DB, API, AI providers, etc.).
abstract class ChatRepository {
  // ===== Session Management =====
  Future<Either<Failure, ChatSession>> createSession(String userId);
  Future<Either<Failure, List<ChatSession>>> getSessions(String userId);
  Future<Either<Failure, ChatSession>> getSessionById(String sessionId);
  Future<Either<Failure, Unit>> deleteSession(String sessionId);

  Future<Either<Failure, Unit>> updateSessionTitle({
    required String sessionId,
    required String newTitle,
  });

  // ===== Message Management =====
  Future<Either<Failure, ChatMessage>> saveMessage(ChatMessage message);
  Future<Either<Failure, List<ChatMessage>>> getMessages(String sessionId);

  Future<Either<Failure, Unit>> updateMessageStatus({
    required String messageId,
    required MessageStatus status,
    String? error,
  });

  Future<Either<Failure, Unit>> deleteMessage(String messageId);

  Stream<List<ChatMessage>>? watchMessages(String sessionId);

  // ===== AI Operations =====
  Future<Either<Failure, String>> getAIResponse({
    required String userId,
    required String message,
    required String sessionId,
    required AIModel model,
    List<ChatMessage>? conversationHistory,
  });

  Future<Either<Failure, AIAnalysisResult>> analyzeMessage({
    required String message,
    required String messageId,
  });
}
