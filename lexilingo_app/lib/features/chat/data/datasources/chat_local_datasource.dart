import 'package:sqflite/sqflite.dart';
import '../../../../core/database/database_helper.dart';
import '../../../../core/error/exceptions.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../../domain/entities/chat_message.dart';

/// Abstract interface for local chat data source
abstract class ChatLocalDataSource {
  // Session operations
  Future<ChatSessionModel> createSession(ChatSessionModel session);
  Future<List<ChatSessionModel>> getSessions(String userId);
  Future<ChatSessionModel> getSessionById(String sessionId);
  Future<void> deleteSession(String sessionId);
  Future<void> updateSessionTitle(String sessionId, String newTitle);
  Future<void> updateSessionLastMessageTime(String sessionId, DateTime time);

  // Message operations
  Future<ChatMessageModel> saveMessage(ChatMessageModel message);
  Future<List<ChatMessageModel>> getMessages(String sessionId);
  Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status, [
    String? error,
  ]);
  Future<void> deleteMessage(String messageId);
}

/// Implementation of local data source using SQLite
class ChatLocalDataSourceImpl implements ChatLocalDataSource {
  final DatabaseHelper databaseHelper;

  ChatLocalDataSourceImpl({required this.databaseHelper});

  // ===== Session Operations =====

  @override
  Future<ChatSessionModel> createSession(ChatSessionModel session) async {
    try {
      final db = await databaseHelper.database;
      await db.insert(
        'chat_sessions',
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return session;
    } catch (e) {
      throw CacheException('Failed to create session: $e');
    }
  }

  @override
  Future<List<ChatSessionModel>> getSessions(String userId) async {
    try {
      final db = await databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'chat_sessions',
        where: 'user_id = ?',
        whereArgs: [userId],
        orderBy: 'last_message_at DESC, created_at DESC',
      );

      return List.generate(maps.length, (i) {
        return ChatSessionModel.fromMap(maps[i]);
      });
    } catch (e) {
      throw CacheException('Failed to get sessions: $e');
    }
  }

  @override
  Future<ChatSessionModel> getSessionById(String sessionId) async {
    try {
      final db = await databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'chat_sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw CacheException('Session not found');
      }

      // Load session with its messages
      final session = ChatSessionModel.fromMap(maps.first);
      final messages = await getMessages(sessionId);

      return session.copyWith(messages: messages) as ChatSessionModel;
    } catch (e) {
      if (e is CacheException) rethrow;
      throw CacheException('Failed to get session: $e');
    }
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    try {
      final db = await databaseHelper.database;
      await db.transaction((txn) async {
        // Delete messages first (cascade should handle this, but being explicit)
        await txn.delete(
          'chat_messages',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        // Delete session
        await txn.delete(
          'chat_sessions',
          where: 'id = ?',
          whereArgs: [sessionId],
        );
      });
    } catch (e) {
      throw CacheException('Failed to delete session: $e');
    }
  }

  @override
  Future<void> updateSessionTitle(String sessionId, String newTitle) async {
    try {
      final db = await databaseHelper.database;
      await db.update(
        'chat_sessions',
        {'title': newTitle},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      throw CacheException('Failed to update session title: $e');
    }
  }

  @override
  Future<void> updateSessionLastMessageTime(
    String sessionId,
    DateTime time,
  ) async {
    try {
      final db = await databaseHelper.database;
      await db.update(
        'chat_sessions',
        {'last_message_at': time.millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      throw CacheException(
          'Failed to update session last message time: $e');
    }
  }

  // ===== Message Operations =====

  @override
  Future<ChatMessageModel> saveMessage(ChatMessageModel message) async {
    try {
      final db = await databaseHelper.database;
      await db.insert(
        'chat_messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // Update session's last_message_at
      await updateSessionLastMessageTime(
        message.sessionId,
        message.timestamp,
      );

      return message;
    } catch (e) {
      throw CacheException('Failed to save message: $e');
    }
  }

  @override
  Future<List<ChatMessageModel>> getMessages(String sessionId) async {
    try {
      final db = await databaseHelper.database;
      final List<Map<String, dynamic>> maps = await db.query(
        'chat_messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'timestamp ASC',
      );

      return List.generate(maps.length, (i) {
        return ChatMessageModel.fromMap(maps[i]);
      });
    } catch (e) {
      throw CacheException('Failed to get messages: $e');
    }
  }

  @override
  Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status, [
    String? error,
  ]) async {
    try {
      final db = await databaseHelper.database;
      await db.update(
        'chat_messages',
        {
          'status': status.toShortString(),
          'error': error,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      throw CacheException('Failed to update message status: $e');
    }
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    try {
      final db = await databaseHelper.database;
      await db.delete(
        'chat_messages',
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      throw CacheException('Failed to delete message: $e');
    }
  }
}
