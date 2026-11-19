import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart';
import 'package:lexilingo_app/features/lexi_chat/data/repositories/lexi_chat_repository_impl.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

class _StubLexiChatDataSource extends LexiChatDataSource {
  _StubLexiChatDataSource()
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

  LexiMessagesMetadata metadataResult = const LexiMessagesMetadata(
    totalCount: 0,
    hasMessages: false,
    latestCursor: null,
    oldestCursor: null,
    latestTs: null,
    oldestTs: null,
  );

  LexiMessagesPage pagedResult = const LexiMessagesPage(
    messages: [],
    hasMore: false,
    nextCursor: null,
    returned: 0,
  );

  @override
  Future<LexiMessagesMetadata> getMessagesMetadata({
    required String sessionId,
  }) async {
    metadataCalls += 1;
    lastMetadataSessionId = sessionId;
    if (metadataError != null) {
      throw metadataError!;
    }
    return metadataResult;
  }

  @override
  Future<LexiMessagesPage> getMessagesPaged({
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
  late _StubLexiChatDataSource dataSource;
  late LexiChatRepositoryImpl repository;

  setUp(() {
    dataSource = _StubLexiChatDataSource();
    repository = LexiChatRepositoryImpl(dataSource: dataSource);
  });

  group('getMessagesPaged', () {
    test('first page is one paged request, no metadata probe', () async {
      final result = await repository.getMessagesPaged(sessionId: 'session_1');

      expect(result.messages, isEmpty);
      expect(dataSource.metadataCalls, 0);
      expect(dataSource.pagedCalls, 1);
      expect(dataSource.lastPagedSessionId, 'session_1');
      expect(dataSource.lastPagedCursor, isNull);
    });

    test('older pages forward the cursor', () async {
      await repository.getMessagesPaged(
        sessionId: 'session_1',
        limit: 20,
        cursor: 'cursor_abc',
      );

      expect(dataSource.metadataCalls, 0);
      expect(dataSource.lastPagedLimit, 20);
      expect(dataSource.lastPagedCursor, 'cursor_abc');
    });

    test('a missing session still surfaces to the provider', () async {
      dataSource.pagedError = Exception('Status 404 session not found');

      await expectLater(
        repository.getMessagesPaged(sessionId: 'gone'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
