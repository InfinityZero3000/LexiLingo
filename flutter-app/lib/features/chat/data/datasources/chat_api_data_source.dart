import 'dart:convert';

import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import '../../../../core/error/exceptions.dart';
import '../models/chat_session_model.dart';
import '../models/chat_message_model.dart';
import '../../domain/entities/chat_message.dart';

const _tag = 'ChatApiDataSource';

class ChatMessagesPageResult {
  final List<ChatMessageModel> messages;
  final bool hasMore;
  final String? nextCursor;
  final int returned;

  const ChatMessagesPageResult({
    required this.messages,
    required this.hasMore,
    required this.nextCursor,
    required this.returned,
  });
}

class ChatMessagesMetadataResult {
  final int totalCount;
  final bool hasMessages;
  final String? latestCursor;
  final String? oldestCursor;
  final String? latestTs;
  final String? oldestTs;

  const ChatMessagesMetadataResult({
    required this.totalCount,
    required this.hasMessages,
    required this.latestCursor,
    required this.oldestCursor,
    required this.latestTs,
    required this.oldestTs,
  });
}

/// Remote data source that talks to the FastAPI backend for chat.
class ChatApiDataSource {
  final ApiClient apiClient;

  ChatApiDataSource({required this.apiClient});

  Future<ChatSessionModel> createSession({
    required String userId,
    String? title,
  }) async {
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
      return sessions
          .map((e) => _mapSession(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ServerException('Unexpected sessions response');
  }

  Future<List<ChatMessageModel>> getMessages(String sessionId) async {
    // Guard against empty session ID
    if (sessionId.isEmpty) {
      logWarn(_tag, 'getMessages called with empty sessionId');
      return [];
    }
    final json = await apiClient.get(
      '/chat/sessions/$sessionId/messages?limit=0',
    );
    final messages = (json['data'] ?? json['messages'] ?? json) as dynamic;
    if (messages is List) {
      return messages
          .map((e) => _mapMessage(Map<String, dynamic>.from(e)))
          .toList();
    }
    throw ServerException('Unexpected messages response');
  }

  Future<ChatMessagesPageResult> getMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) async {
    if (sessionId.isEmpty) {
      logWarn(_tag, 'getMessagesPaged called with empty sessionId');
      return const ChatMessagesPageResult(
        messages: [],
        hasMore: false,
        nextCursor: null,
        returned: 0,
      );
    }

    final safeLimit = limit < 1 ? 1 : (limit > 200 ? 200 : limit);

    try {
      final query = StringBuffer('limit=$safeLimit');
      if (cursor != null && cursor.isNotEmpty) {
        query.write('&cursor=${Uri.encodeComponent(cursor)}');
      }

      final json = await apiClient.get(
        '/chat/sessions/$sessionId/messages/paged?${query.toString()}',
      );

      final data = json['data'] ?? json;
      final dynamic rawMessages = data['messages'] ?? data['data'] ?? [];
      final pagination = Map<String, dynamic>.from(
        (data['pagination'] ?? const <String, dynamic>{}) as Map,
      );

      if (rawMessages is! List) {
        throw ServerException('Unexpected paged messages response');
      }

      final parsedMessages = rawMessages
          .map((e) => _mapMessage(Map<String, dynamic>.from(e)))
          .toList();

      return ChatMessagesPageResult(
        messages: parsedMessages,
        hasMore: pagination['has_more'] == true,
        nextCursor: pagination['next_cursor']?.toString(),
        returned:
            (pagination['returned'] as num?)?.toInt() ?? parsedMessages.length,
      );
    } catch (e) {
      logWarn(
        _tag,
        'Paged endpoint failed, fallback to legacy getMessages: $e',
      );
      final allMessages = await getMessages(sessionId);
      return _fallbackPageFromAll(
        allMessages: allMessages,
        limit: safeLimit,
        cursor: cursor,
      );
    }
  }

  Future<ChatMessagesMetadataResult> getMessagesMetadata(
    String sessionId,
  ) async {
    if (sessionId.isEmpty) {
      return const ChatMessagesMetadataResult(
        totalCount: 0,
        hasMessages: false,
        latestCursor: null,
        oldestCursor: null,
        latestTs: null,
        oldestTs: null,
      );
    }

    final json = await apiClient.get(
      '/chat/sessions/$sessionId/messages/metadata',
    );
    final data = json['data'] ?? json;
    final metadata = Map<String, dynamic>.from(
      (data['metadata'] ?? const <String, dynamic>{}) as Map,
    );

    final totalCount = (metadata['total_count'] as num?)?.toInt() ?? 0;
    return ChatMessagesMetadataResult(
      totalCount: totalCount,
      hasMessages: metadata['has_messages'] == true,
      latestCursor: metadata['latest_cursor']?.toString(),
      oldestCursor: metadata['oldest_cursor']?.toString(),
      latestTs: metadata['latest_ts']?.toString(),
      oldestTs: metadata['oldest_ts']?.toString(),
    );
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
    final response =
        data['ai_response'] ??
        data['response'] ??
        data['message'] ??
        data['reply'];
    if (response is String && response.isNotEmpty) {
      return response;
    }
    throw ServerException('AI response missing');
  }

  ChatSessionModel _mapSession(Map<String, dynamic> json) {
    // Accept both snake_case and camelCase, including session_id from AI service
    final id =
        json['id']?.toString() ??
        json['session_id']?.toString() ??
        json['sessionId']?.toString() ??
        json['_id']?.toString() ??
        '';
    logDebug(
      _tag,
      '_mapSession: json keys=${json.keys.toList()}, extracted id=$id',
    );
    return ChatSessionModel(
      id: id,
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Chat Session',
      createdAt: _parseDate(json['created_at'] ?? json['createdAt']),
      lastMessageAt: _tryParseDate(
        json['last_message_at'] ??
            json['lastMessageAt'] ??
            json['last_activity'],
      ),
      messages: null,
    );
  }

  ChatMessageModel _mapMessage(Map<String, dynamic> json) {
    final roleRaw = (json['role'] ?? json['sender'] ?? 'ai')
        .toString()
        .toLowerCase();
    final role = roleRaw == 'user' ? MessageRole.user : MessageRole.ai;
    final statusRaw = (json['status'] ?? 'sent').toString();
    final status = _safeStatus(statusRaw);
    return ChatMessageModel(
      id: json['id']?.toString() ?? json['_id']?.toString() ?? '',
      sessionId:
          json['session_id']?.toString() ?? json['sessionId']?.toString() ?? '',
      content: json['content']?.toString() ?? json['message']?.toString() ?? '',
      role: role,
      timestamp: _parseDate(
        json['timestamp'] ?? json['created_at'] ?? json['createdAt'],
      ),
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

  ChatMessagesPageResult _fallbackPageFromAll({
    required List<ChatMessageModel> allMessages,
    required int limit,
    required String? cursor,
  }) {
    if (allMessages.isEmpty) {
      return const ChatMessagesPageResult(
        messages: [],
        hasMore: false,
        nextCursor: null,
        returned: 0,
      );
    }

    int endIndex = allMessages.length;
    if (cursor != null && cursor.isNotEmpty) {
      final cursorParts = _decodeCursorBestEffort(cursor);
      final cursorId = cursorParts['id'];
      final cursorTs = cursorParts['timestamp'];
      final idx = allMessages.indexWhere((m) {
        final sameId = cursorId != null && m.id == cursorId;
        final sameTs =
            cursorTs != null &&
            m.timestamp.toIso8601String().startsWith(cursorTs);
        return sameId || sameTs;
      });
      if (idx >= 0) {
        endIndex = idx;
      }
    }

    final startIndex = (endIndex - limit) < 0 ? 0 : (endIndex - limit);
    final page = allMessages.sublist(startIndex, endIndex);
    final hasMore = startIndex > 0;
    final nextCursor = hasMore && page.isNotEmpty
        ? _encodeLocalCursor(page.first)
        : null;

    return ChatMessagesPageResult(
      messages: page,
      hasMore: hasMore,
      nextCursor: nextCursor,
      returned: page.length,
    );
  }

  String _encodeLocalCursor(ChatMessageModel message) {
    final payload = '${message.timestamp.toIso8601String()}|${message.id}';
    return base64UrlEncode(utf8.encode(payload));
  }

  Map<String, String?> _decodeCursorBestEffort(String cursor) {
    try {
      final raw = utf8.decode(base64Url.decode(cursor));
      final parts = raw.split('|');
      if (parts.length < 2) {
        return {'timestamp': null, 'id': null};
      }
      return {'timestamp': parts[0], 'id': parts[1]};
    } catch (_) {
      return {'timestamp': null, 'id': null};
    }
  }
}
