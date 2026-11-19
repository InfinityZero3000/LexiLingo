import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_api_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_local_datasource.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lexilingo_app/features/chat/data/models/chat_message_model.dart';
import 'package:lexilingo_app/features/chat/data/models/chat_session_model.dart';
import 'package:lexilingo_app/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:lexilingo_app/features/chat/domain/entities/chat_message.dart';

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

class _StubChatLocalDataSource implements ChatLocalDataSource {
  List<ChatMessageModel> messages = const [];

  @override
  Future<ChatSessionModel> createSession(ChatSessionModel session) async =>
      session;

  @override
  Future<void> deleteMessage(String messageId) async {}

  @override
  Future<void> deleteSession(String sessionId) async {}

  @override
  Future<List<ChatMessageModel>> getMessages(String sessionId) async =>
      messages;

  @override
  Future<ChatSessionModel> getSessionById(String sessionId) async {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatSessionModel>> getSessions(String userId) async {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessageModel> saveMessage(ChatMessageModel message) async =>
      message;

  @override
  Future<void> updateMessageStatus(
    String messageId,
    MessageStatus status, [
    String? error,
  ]) async {}

  @override
  Future<void> updateSessionLastMessageTime(
    String sessionId,
    DateTime time,
  ) async {}

  @override
  Future<void> updateSessionTitle(String sessionId, String newTitle) async {}
}

class _StubChatRemoteDataSource extends ChatRemoteDataSource {
  _StubChatRemoteDataSource() : super(apiKey: 'test-key');
}

class _StubChatApiDataSource extends ChatApiDataSource {
  _StubChatApiDataSource()
    : super(
        apiClient: ApiClient(
          baseUrl: 'http://localhost:8000',
          enableLogging: false,
          networkInfo: _AlwaysConnectedNetworkInfo(),
        ),
      );

  int metadataCalls = 0;
  int pagedCalls = 0;
  String? lastMetadataSessionId;
  String? lastPagedSessionId;
  int? lastPagedLimit;
  String? lastPagedCursor;

  Object? metadataError;
  Object? pagedError;

  ChatMessagesMetadataResult metadataResult = const ChatMessagesMetadataResult(
    totalCount: 0,
    hasMessages: false,
    latestCursor: null,
    oldestCursor: null,
    latestTs: null,
    oldestTs: null,
  );

  ChatMessagesPageResult pagedResult = const ChatMessagesPageResult(
    messages: [],
    hasMore: false,
    nextCursor: null,
    returned: 0,
  );

  @override
  Future<ChatMessagesMetadataResult> getMessagesMetadata(
    String sessionId,
  ) async {
    metadataCalls += 1;
    lastMetadataSessionId = sessionId;
    if (metadataError != null) {
      throw metadataError!;
    }
    return metadataResult;
  }

  @override
  Future<ChatMessagesPageResult> getMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) async {
    pagedCalls += 1;
    lastPagedSessionId = sessionId;
    lastPagedLimit = limit;
    lastPagedCursor = cursor;
    if (pagedError != null) {
      throw pagedError!;
    }
    return pagedResult;
  }
}

void main() {
  late ChatRepositoryImpl repository;
  late _StubChatLocalDataSource localDataSource;
  late _StubChatRemoteDataSource remoteDataSource;
  late _AlwaysConnectedNetworkInfo networkInfo;
  late _StubChatApiDataSource apiDataSource;

  setUp(() {
    localDataSource = _StubChatLocalDataSource();
    remoteDataSource = _StubChatRemoteDataSource();
    networkInfo = _AlwaysConnectedNetworkInfo();
    apiDataSource = _StubChatApiDataSource();

    repository = ChatRepositoryImpl(
      localDataSource: localDataSource,
      remoteDataSource: remoteDataSource,
      networkInfo: networkInfo,
      apiDataSource: apiDataSource,
    );
  });

  group('getMessagesPaged', () {
    test('first page is one paged request, no metadata probe', () async {
      final result = await repository.getMessagesPaged('session_1');

      expect(result.isRight(), true);
      expect(apiDataSource.metadataCalls, 0);
      expect(apiDataSource.pagedCalls, 1);
      expect(apiDataSource.lastPagedSessionId, 'session_1');
      expect(apiDataSource.lastPagedCursor, isNull);
    });

    test('older pages forward the cursor', () async {
      await repository.getMessagesPaged(
        'session_1',
        limit: 20,
        cursor: 'cursor_abc',
      );

      expect(apiDataSource.metadataCalls, 0);
      expect(apiDataSource.lastPagedLimit, 20);
      expect(apiDataSource.lastPagedCursor, 'cursor_abc');
    });
  });
}
