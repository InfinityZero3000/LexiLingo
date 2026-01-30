import 'package:dartz/dartz.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_session.dart';
import '../../domain/entities/ai_analysis_result.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_local_datasource.dart';
import '../datasources/chat_api_data_source.dart';
import '../datasources/chat_remote_data_source.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';

/// Implementation of ChatRepository
/// Connects local and remote data sources
class ChatRepositoryImpl implements ChatRepository {
  final ChatLocalDataSource localDataSource;
  final ChatRemoteDataSource remoteDataSource;
  final NetworkInfo networkInfo;
  final ChatApiDataSource? apiDataSource;

  ChatRepositoryImpl({
    required this.localDataSource,
    required this.remoteDataSource,
    required this.networkInfo,
    this.apiDataSource,
  });

  // ===== Session Management =====

  @override
  Future<Either<Failure, ChatSession>> createSession(String userId) async {
    try {
      if (apiDataSource != null && await networkInfo.isConnected) {
        try {
          final session = await apiDataSource!.createSession(userId: userId);
          // Cache locally for offline use
          await localDataSource.createSession(session);
          return Right(session.toEntity());
        } catch (e) {
          // If API fails (e.g., 404), fallback to local
          print('[WARN] Chat API not available, creating local session: $e');
        }
      }

      final now = DateTime.now();
      final title = 'Chat ${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute}';

      final session = ChatSessionModel(
        id: _generateId(),
        userId: userId,
        title: title,
        createdAt: now,
        lastMessageAt: null,
        messages: [],
      );

      final result = await localDataSource.createSession(session);
      return Right(result.toEntity());
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to create session: $e'));
    }
  }

  @override
  Future<Either<Failure, List<ChatSession>>> getSessions(String userId) async {
    try {
      if (apiDataSource != null && await networkInfo.isConnected) {
        try {
          final sessions = await apiDataSource!.getSessions(userId);
          // Optionally cache
          return Right(sessions.map((s) => s.toEntity()).toList());
        } catch (e) {
          // If API fails (e.g., 404), fallback to local
          print('[WARN] Chat API not available, using local storage: $e');
        }
      }

      final sessions = await localDataSource.getSessions(userId);
      return Right(sessions.map((s) => s.toEntity()).toList());
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to get sessions: $e'));
    }
  }

  @override
  Future<Either<Failure, ChatSession>> getSessionById(String sessionId) async {
    try {
      final session = await localDataSource.getSessionById(sessionId);
      return Right(session.toEntity());
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to get session: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteSession(String sessionId) async {
    try {
      await localDataSource.deleteSession(sessionId);
      return const Right(unit);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to delete session: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateSessionTitle({
    required String sessionId,
    required String newTitle,
  }) async {
    try {
      await localDataSource.updateSessionTitle(sessionId, newTitle);
      return const Right(unit);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to update session title: $e'));
    }
  }

  // ===== Message Management =====

  @override
  Future<Either<Failure, ChatMessage>> saveMessage(ChatMessage message) async {
    try {
      final messageModel = ChatMessageModel.fromEntity(message);
      final result = await localDataSource.saveMessage(messageModel);
      return Right(result.toEntity());
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to save message: $e'));
    }
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> getMessages(String sessionId) async {
    try {
      if (apiDataSource != null && await networkInfo.isConnected) {
        final messages = await apiDataSource!.getMessages(sessionId);
        return Right(messages.map((m) => m.toEntity()).toList());
      }

      final messages = await localDataSource.getMessages(sessionId);
      return Right(messages.map((m) => m.toEntity()).toList());
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to get messages: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateMessageStatus({
    required String messageId,
    required MessageStatus status,
    String? error,
  }) async {
    try {
      await localDataSource.updateMessageStatus(messageId, status, error);
      return const Right(unit);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to update message status: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteMessage(String messageId) async {
    try {
      await localDataSource.deleteMessage(messageId);
      return const Right(unit);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to delete message: $e'));
    }
  }

  // ===== AI Operations =====

  @override
  Future<Either<Failure, String>> getAIResponse({
    required String userId,
    required String message,
    required String sessionId,
    required AIModel model,
    List<ChatMessage>? conversationHistory,
  }) async {
    if (!await networkInfo.isConnected) {
      return const Left(NetworkFailure('No internet connection'));
    }

    try {
      if (apiDataSource != null) {
        final response = await apiDataSource!.sendMessage(
          userId: userId,
          sessionId: sessionId,
          message: message,
        );
        return Right(response);
      }

      List<ChatMessageModel>? historyModels;
      if (conversationHistory != null) {
        historyModels = conversationHistory
            .map((m) => ChatMessageModel.fromEntity(m))
            .toList();
      }

      final response = await remoteDataSource.getAIResponse(
        message: message,
        sessionId: sessionId,
        model: model,
        conversationHistory: historyModels,
      );

      return Right(response);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } catch (e) {
      return Left(ServerFailure('Failed to get AI response: $e'));
    }
  }

  @override
  Future<Either<Failure, AIAnalysisResult>> analyzeMessage({
    required String message,
    required String messageId,
  }) async {
    return Right(AIAnalysisResult(
      messageId: messageId,
      fluency: null,
      vocabularyLevel: null,
      grammarErrors: [],
      correctedText: null,
      analyzedAt: DateTime.now(),
    ));
  }

  @override
  Stream<List<ChatMessage>>? watchMessages(String sessionId) {
    return null;
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        '_' +
        (DateTime.now().microsecond % 1000).toString();
  }
}
