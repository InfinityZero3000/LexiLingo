import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import '../../../../core/error/exceptions.dart';
import '../models/chat_session_model.dart';
import '../models/chat_message_model.dart';
import '../../domain/entities/chat_message.dart';

const _tag = 'ChatApiDataSource';

/// Remote data source that talks to the FastAPI backend for chat.
class ChatApiDataSource {
  final ApiClient apiClient;

  ChatApiDataSource({required this.apiClient});

  Future<ChatSessionModel> createSession({required String userId, String? title}) async {
    final payload = {
      'user_id': userId,
      if (title != null && title.isNotEmpty) 'title': title,
    };
    final json = await apiClient.post('/chat/sessions', body: payload);
    logDebug(_tag, 'createSession response: $json');
    final sessionData = json['data'] ?? json;
    logDebug(_tag, 'sessionData: $sessionData');
    return _mapSession(sessionData);
  }

  Future<List<ChatSessionModel>> getSessions(String userId) async {
    final json = await apiClient.get('/chat/sessions/user/$userId');
    final sessions = (json['data'] ?? json['sessions'] ?? json) as dynamic;
    if (sessions is List) {
      return sessions.map((e) => _mapSession(Map<String, dynamic>.from(e))).toList();
    }
    throw ServerException('Unexpected sessions response');
  }

  Future<List<ChatMessageModel>> getMessages(String sessionId) async {
    // Guard against empty session ID
    if (sessionId.isEmpty) {
      logWarn(_tag, 'getMessages called with empty sessionId');
      return [];
    }
    final json = await apiClient.get('/chat/sessions/$sessionId/messages');
    final messages = (json['data'] ?? json['messages'] ?? json) as dynamic;
    if (messages is List) {
      return messages.map((e) => _mapMessage(Map<String, dynamic>.from(e))).toList();
    }
    throw ServerException('Unexpected messages response');
  }

  /// Send user message and get AI reply from backend.
  Future<String> sendMessage({
    required String userId,
    required String sessionId,
    required String message,
  }) async {
    // Guard against empty session ID
    if (sessionId.isEmpty) {
      throw ServerException('Cannot send message: session ID is empty');
    }
    final payload = {
      'user_id': userId,
      'session_id': sessionId,
      'message': message,
    };
    final json = await apiClient.post(
      '/chat/messages',
      body: payload,
      timeout: AppConstants.aiOperationTimeout,
    );
    // Backend may return {data: {ai_response: '...'}} or {ai_response: '...'}
    final data = json['data'] ?? json;
    final response = data['ai_response'] ?? data['response'] ?? data['message'] ?? data['reply'];
    if (response is String && response.isNotEmpty) {
      return response;
    }
    throw ServerException('AI response missing');
  }

  ChatSessionModel _mapSession(Map<String, dynamic> json) {
    // Accept both snake_case and camelCase, including session_id from AI service
    final id = json['id']?.toString() ?? 
        json['session_id']?.toString() ?? 
        json['sessionId']?.toString() ?? 
        json['_id']?.toString() ?? '';
    logDebug(_tag, '_mapSession: json keys=${json.keys.toList()}, extracted id=$id');
    return ChatSessionModel(
      id: id,
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Chat Session',
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      lastMessageAt: _tryParseDate(json['last_message_at'] ?? json['lastMessageAt'] ?? json['last_activity']),
      messages: null,
    );
  }

  ChatMessageModel _mapMessage(Map<String, dynamic> json) {
    final roleRaw = (json['role'] ?? json['sender'] ?? 'ai').toString().toLowerCase();
    final role = roleRaw == 'user' ? MessageRole.user : MessageRole.ai;
    final statusRaw = (json['status'] ?? 'sent').toString();
    final status = _safeStatus(statusRaw);
    return ChatMessageModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      sessionId: json['session_id']?.toString() ?? json['sessionId']?.toString() ?? '',
      content: json['content']?.toString() ?? json['message']?.toString() ?? '',
      role: role,
      timestamp: _parseDate(json['timestamp'] ?? json['created_at'] ?? json['createdAt']),
      status: status,
      error: json['error']?.toString(),
    );
  }

  DateTime _parseDate(Object? value) {
    if (value == null) return DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString()) ?? DateTime.now();
  }

  DateTime? _tryParseDate(Object? value) {
    if (value == null) return null;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.tryParse(value.toString());
  }

  MessageStatus _safeStatus(String raw) {
    final lower = raw.toLowerCase();
    if (lower == 'sending') return MessageStatus.sending;
    if (lower == 'error') return MessageStatus.error;
    return MessageStatus.sent;
  }
}
