import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/chat/data/datasources/story_api_data_source.dart';
import 'package:lexilingo_app/features/chat/data/models/topic_session_model.dart';
import 'package:lexilingo_app/features/chat/data/repositories/story_repository_impl.dart';

class _StubStoryApiDataSource extends StoryApiDataSource {
  _StubStoryApiDataSource() : super(baseUrl: 'http://localhost:8001');

  int metadataCalls = 0;
  int pagedCalls = 0;
  String? lastMetadataSessionId;
  String? lastPagedSessionId;
  int? lastPagedLimit;
  String? lastPagedCursor;

  Object? metadataError;
  Object? pagedError;

  TopicMessagesMetadataResult metadataResult =
      const TopicMessagesMetadataResult(
        totalCount: 0,
        hasMessages: false,
        latestCursor: null,
        oldestCursor: null,
        latestTs: null,
        oldestTs: null,
      );

  TopicMessagesPageResult pagedResult = const TopicMessagesPageResult(
    messages: [],
    hasMore: false,
    nextCursor: null,
    returned: 0,
  );

  @override
  Future<TopicMessagesMetadataResult> getTopicMessagesMetadata(
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
  Future<TopicMessagesPageResult> getTopicMessagesPaged({
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
  late _StubStoryApiDataSource apiDataSource;
  late StoryRepositoryImpl repository;

  setUp(() {
    apiDataSource = _StubStoryApiDataSource();
    repository = StoryRepositoryImpl(apiDataSource: apiDataSource);
  });

  group('getTopicMessagesPaged metadata-first', () {
    test(
      'returns empty page immediately when metadata has no messages',
      () async {
        apiDataSource.metadataResult = const TopicMessagesMetadataResult(
          totalCount: 0,
          hasMessages: false,
          latestCursor: null,
          oldestCursor: null,
          latestTs: null,
          oldestTs: null,
        );

        final result = await repository.getTopicMessagesPaged(
          'topic_session_1',
        );

        expect(result.isRight(), true);
        result.fold(
          (failure) => fail('Expected Right but got Left: $failure'),
          (page) {
            expect(page.messages, isEmpty);
            expect(page.hasMore, false);
            expect(page.nextCursor, isNull);
            expect(page.returned, 0);
          },
        );
        expect(apiDataSource.metadataCalls, 1);
        expect(apiDataSource.pagedCalls, 0);
        expect(apiDataSource.lastMetadataSessionId, 'topic_session_1');
      },
    );

    test(
      'continues to paged endpoint when metadata indicates messages exist',
      () async {
        apiDataSource.metadataResult = const TopicMessagesMetadataResult(
          totalCount: 12,
          hasMessages: true,
          latestCursor: 'latest',
          oldestCursor: 'oldest',
          latestTs: '2026-04-16T00:00:10Z',
          oldestTs: '2026-04-16T00:00:00Z',
        );
        apiDataSource.pagedResult = TopicMessagesPageResult(
          messages: [
            TopicChatMessage(
              id: 'm1',
              sessionId: 'topic_session_1',
              content: 'hello topic',
              isUser: true,
              timestamp: DateTime.parse('2026-04-16T00:00:00Z'),
            ),
          ],
          hasMore: true,
          nextCursor: 'next-cursor',
          returned: 1,
        );

        final result = await repository.getTopicMessagesPaged(
          'topic_session_1',
        );

        expect(result.isRight(), true);
        result.fold(
          (failure) => fail('Expected Right but got Left: $failure'),
          (page) {
            expect(page.messages.length, 1);
            expect(page.messages.first.id, 'm1');
            expect(page.hasMore, true);
            expect(page.nextCursor, 'next-cursor');
            expect(page.returned, 1);
          },
        );
        expect(apiDataSource.metadataCalls, 1);
        expect(apiDataSource.pagedCalls, 1);
        expect(apiDataSource.lastPagedSessionId, 'topic_session_1');
        expect(apiDataSource.lastPagedLimit, 50);
        expect(apiDataSource.lastPagedCursor, isNull);
      },
    );

    test('still calls paged endpoint when metadata request throws', () async {
      apiDataSource.metadataError = Exception('metadata unavailable');
      apiDataSource.pagedResult = TopicMessagesPageResult(
        messages: [
          TopicChatMessage(
            id: 'm2',
            sessionId: 'topic_session_1',
            content: 'fallback path',
            isUser: false,
            timestamp: DateTime.parse('2026-04-16T00:01:00Z'),
          ),
        ],
        hasMore: false,
        nextCursor: null,
        returned: 1,
      );

      final result = await repository.getTopicMessagesPaged('topic_session_1');

      expect(result.isRight(), true);
      result.fold((failure) => fail('Expected Right but got Left: $failure'), (
        page,
      ) {
        expect(page.messages.length, 1);
        expect(page.messages.first.id, 'm2');
        expect(page.returned, 1);
      });
      expect(apiDataSource.metadataCalls, 1);
      expect(apiDataSource.pagedCalls, 1);
    });

    test('skips metadata check when cursor is provided', () async {
      apiDataSource.pagedResult = const TopicMessagesPageResult(
        messages: [],
        hasMore: false,
        nextCursor: null,
        returned: 0,
      );

      final result = await repository.getTopicMessagesPaged(
        'topic_session_1',
        limit: 20,
        cursor: 'cursor-1',
      );

      expect(result.isRight(), true);
      result.fold((failure) => fail('Expected Right but got Left: $failure'), (
        page,
      ) {
        expect(page.messages, isEmpty);
        expect(page.returned, 0);
        expect(page.hasMore, false);
      });
      expect(apiDataSource.metadataCalls, 0);
      expect(apiDataSource.pagedCalls, 1);
      expect(apiDataSource.lastPagedLimit, 20);
      expect(apiDataSource.lastPagedCursor, 'cursor-1');
    });

    test(
      'returns ServerFailure when paged endpoint throws ServerException',
      () async {
        apiDataSource.metadataResult = const TopicMessagesMetadataResult(
          totalCount: 5,
          hasMessages: true,
          latestCursor: 'latest',
          oldestCursor: 'oldest',
          latestTs: '2026-04-16T00:00:10Z',
          oldestTs: '2026-04-16T00:00:00Z',
        );
        apiDataSource.pagedError = ServerException('paged failed');

        final result = await repository.getTopicMessagesPaged(
          'topic_session_1',
        );

        expect(result.isLeft(), true);
        result.fold((failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, 'paged failed');
        }, (_) => fail('Expected Left but got Right'));
        expect(apiDataSource.metadataCalls, 1);
        expect(apiDataSource.pagedCalls, 1);
      },
    );
  });
}
