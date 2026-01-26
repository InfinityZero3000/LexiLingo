import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'chat_local_datasource.dart';
import '../models/chat_message_model.dart';
import '../models/chat_session_model.dart';
import '../../domain/entities/chat_message.dart';

/// Web implementation of ChatLocalDataSource using SharedPreferences
class ChatLocalDataSourceWeb implements ChatLocalDataSource {
  final SharedPreferences sharedPreferences;
  
  static const String _sessionsKey = 'chat_sessions';
  static const String _messagesKey = 'chat_messages_';
  
  ChatLocalDataSourceWeb({required this.sharedPreferences});

  @override
  Future<ChatSessionModel> createSession(ChatSessionModel session) async {
    final sessions = await getSessions(session.userId);
    sessions.add(session);
    await _saveSessions(sessions);
    return session;
  }

  @override
  Future<ChatSessionModel> getSessionById(String sessionId) async {
    final jsonString = sharedPreferences.getString(_sessionsKey);
    if (jsonString == null) throw Exception('Session not found');
    
    final List<dynamic> jsonList = json.decode(jsonString);
    final sessions = jsonList.map((json) => ChatSessionModel.fromJson(json)).toList();
    
    return sessions.firstWhere(
      (s) => s.id == sessionId,
      orElse: () => throw Exception('Session not found'),
    );
  }

  @override
  Future<List<ChatSessionModel>> getSessions(String userId) async {
    final jsonString = sharedPreferences.getString(_sessionsKey);
    if (jsonString == null) return [];
    
    final List<dynamic> jsonList = json.decode(jsonString);
    final allSessions = jsonList.map((json) => ChatSessionModel.fromJson(json)).toList();
    return allSessions.where((s) => s.userId == userId).toList();
  }

  @override
  Future<void> deleteSession(String sessionId) async {
    final jsonString = sharedPreferences.getString(_sessionsKey);
    if (jsonString != null) {
      final List<dynamic> jsonList = json.decode(jsonString);
      final sessions = jsonList.map((json) => ChatSessionModel.fromJson(json)).toList();
      sessions.removeWhere((s) => s.id == sessionId);
      await _saveSessions(sessions);
    }
    
    // Delete messages too
    await sharedPreferences.remove('$_messagesKey$sessionId');
  }

  @override
  Future<void> updateSessionTitle(String sessionId, String newTitle) async {
    final session = await getSessionById(sessionId);
    final sessions = await getSessions(session.userId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      final updated = ChatSessionModel(
        id: session.id,
        userId: session.userId,
        title: newTitle,
        createdAt: session.createdAt,
        lastMessageAt: session.lastMessageAt,
        messages: session.messages,
      );
      sessions[index] = updated;
      await _saveSessions(sessions);
    }
  }

  @override
  Future<void> updateSessionLastMessageTime(String sessionId, DateTime time) async {
    final session = await getSessionById(sessionId);
    final sessions = await getSessions(session.userId);
    final index = sessions.indexWhere((s) => s.id == sessionId);
    if (index != -1) {
      final updated = ChatSessionModel(
        id: session.id,
        userId: session.userId,
        title: session.title,
        createdAt: session.createdAt,
        lastMessageAt: time,
        messages: session.messages,
      );
      sessions[index] = updated;
      await _saveSessions(sessions);
    }
  }

  @override
  Future<ChatMessageModel> saveMessage(ChatMessageModel message) async {
    final messages = await getMessages(message.sessionId);
    messages.add(message);
    await _saveMessages(message.sessionId, messages);
    return message;
  }

  @override
  Future<List<ChatMessageModel>> getMessages(String sessionId) async {
    final jsonString = sharedPreferences.getString('$_messagesKey$sessionId');
    if (jsonString == null) return [];
    
    final List<dynamic> jsonList = json.decode(jsonString);
    return jsonList.map((json) => ChatMessageModel.fromJson(json)).toList();
  }

  @override
  Future<void> updateMessageStatus(String messageId, MessageStatus status, [String? error]) async {
    // Find the message across all sessions
    final jsonString = sharedPreferences.getString(_sessionsKey);
    if (jsonString == null) return;
    
    final List<dynamic> jsonList = json.decode(jsonString);
    final sessions = jsonList.map((json) => ChatSessionModel.fromJson(json)).toList();
    
    for (final session in sessions) {
      final messages = await getMessages(session.id);
      final index = messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final message = messages[index];
        final updated = ChatMessageModel(
          id: message.id,
          sessionId: message.sessionId,
          content: message.content,
          role: message.role,
          timestamp: message.timestamp,
          status: status,
          error: error,
        );
        messages[index] = updated;
        await _saveMessages(session.id, messages);
        return;
      }
    }
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final jsonString = sharedPreferences.getString(_sessionsKey);
    if (jsonString == null) return;
    
    final List<dynamic> jsonList = json.decode(jsonString);
    final sessions = jsonList.map((json) => ChatSessionModel.fromJson(json)).toList();
    
    for (final session in sessions) {
      final messages = await getMessages(session.id);
      final initialLength = messages.length;
      messages.removeWhere((m) => m.id == messageId);
      if (messages.length < initialLength) {
        await _saveMessages(session.id, messages);
        return;
      }
    }
  }

  // Helper methods
  Future<void> _saveSessions(List<ChatSessionModel> sessions) async {
    final jsonList = sessions.map((s) => s.toJson()).toList();
    await sharedPreferences.setString(_sessionsKey, json.encode(jsonList));
  }

  Future<void> _saveMessages(String sessionId, List<ChatMessageModel> messages) async {
    final jsonList = messages.map((m) => m.toJson()).toList();
    await sharedPreferences.setString('$_messagesKey$sessionId', json.encode(jsonList));
  }
}
