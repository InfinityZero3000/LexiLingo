import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/chat/data/datasources/story_api_data_source.dart';
import 'package:lexilingo_app/features/chat/data/models/topic_session_model.dart';
import 'package:lexilingo_app/features/chat/data/repositories/story_repository_impl.dart';

class _StubStoryApiDataSource extends StoryApiDataSource {
  _StubStoryApiDataSource();

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

  group('getTopicMessagesPaged', () {
    test('first page is one paged request, no metadata probe', () async {
      final result = await repository.getTopicMessagesPaged('topic_session_1');

      expect(result.isRight(), true);
      expect(apiDataSource.metadataCalls, 0);
      expect(apiDataSource.pagedCalls, 1);
      expect(apiDataSource.lastPagedSessionId, 'topic_session_1');
    });

    test('a paged server error maps to a failure', () async {
      apiDataSource.pagedError = ServerException('boom');

      final result = await repository.getTopicMessagesPaged('topic_session_1');

      expect(result.isLeft(), true);
      result.fold((f) => expect(f, isA<ServerFailure>()), (_) => fail('Left'));
    });
  });
}
