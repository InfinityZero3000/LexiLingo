import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/chat/domain/entities/story.dart';
import 'package:lexilingo_app/features/chat/domain/entities/topic_session.dart';
import 'package:lexilingo_app/features/chat/domain/entities/topic_stream_event.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/story_repository.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _story = StoryListItem(
  storyId: 's1',
  title: LocalizedTitle(vi: 'Cafe', en: 'Cafe'),
  difficultyLevel: DifficultyLevel.A1,
  category: 'food',
);

class _Repo implements StoryRepository {
  final streams = <StreamController<TopicStreamEvent>>[];

  @override
  Future<Either<Failure, TopicSession>> startTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'tracecag',
  }) async => Right(
    TopicSession(
      sessionId: 'sess',
      story: _story,
      rolePersona: const RolePersona(
        name: 'Ann',
        role: 'barista',
        personality: 'kind',
        speakingStyle: 'casual',
        background: '',
      ),
      openingMessage: 'Hi',
      createdAt: DateTime(2026),
    ),
  );

  @override
  Stream<TopicStreamEvent> sendTopicMessageStream({
    required String sessionId,
    required String userId,
    required String message,
  }) {
    final controller = StreamController<TopicStreamEvent>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a second send while one is streaming is rejected', () async {
    final repo = _Repo();
    final provider = StoryProvider(repository: repo);
    await provider.startTopicSession(userId: 'u', storyId: 's1');

    final first = provider.sendMessageStreaming(userId: 'u', message: 'one');
    await Future<void>.delayed(Duration.zero);
    expect(provider.isSendingMessage, isTrue);

    final second = await provider.sendMessageStreaming(
      userId: 'u',
      message: 'two',
    );

    expect(second, isFalse);
    expect(repo.streams, hasLength(1));
    expect(provider.messages.where((m) => m.isUser), hasLength(1));

    repo.streams.single.add(const TopicStreamChunk('hi'));
    await repo.streams.single.close();
    await first;
  });

  Future<(StoryProvider, _Repo, int, Future<bool>)> send() async {
    final repo = _Repo();
    final provider = StoryProvider(repository: repo);
    await provider.startTopicSession(userId: 'u', storyId: 's1');
    final before = provider.messages.length;
    final sent = provider.sendMessageStreaming(userId: 'u', message: 'one');
    await Future<void>.delayed(Duration.zero);
    return (provider, repo, before, sent);
  }

  // The server emits `error` before any chunk and saves only after the last
  // one, so a turn with no content was not saved and leaves no bubbles.
  test('an error event removes both bubbles and never re-sends', () async {
    final (provider, repo, before, sent) = await send();
    repo.streams.single.add(
      const TopicStreamError('No safe response available'),
    );
    await repo.streams.single.close();

    expect(await sent, isFalse);
    expect(repo.streams, hasLength(1));
    expect(provider.messages, hasLength(before));
    expect(provider.isSendingMessage, isFalse);
    expect(provider.sessionError, 'errors.genericRetry');
  });

  test('a quota rejection is shown as rate limited, not raw', () async {
    final (provider, repo, before, sent) = await send();
    repo.streams.single.addError(
      ServerException(
        'POST stream /x failed with status 429: {"detail":"quota"}',
      ),
    );
    await repo.streams.single.close();

    expect(await sent, isFalse);
    expect(provider.messages, hasLength(before));
    expect(provider.sessionError, 'errors.rateLimited');
  });

  test('a stream cut after content keeps the reply and reports it', () async {
    final (provider, repo, before, sent) = await send();
    repo.streams.single.add(const TopicStreamChunk('Partial reply'));
    await repo.streams.single.close();

    expect(await sent, isFalse);
    expect(provider.messages, hasLength(before + 2));
    expect(provider.messages.last.content, 'Partial reply');
    expect(provider.isSendingMessage, isFalse);
    expect(provider.sessionError, isNotNull);
  });

  test('done replaces the streamed text with the saved reply', () async {
    final (provider, repo, _, sent) = await send();
    repo.streams.single.add(const TopicStreamChunk('Partial'));
    repo.streams.single.add(
      const TopicStreamDone(
        TopicChatResponse(
          response: 'Completed reply',
          messageIdOverride: 'saved-id',
        ),
      ),
    );
    await repo.streams.single.close();

    expect(await sent, isTrue);
    expect(provider.sessionError, isNull);
    expect(provider.messages.last.id, 'saved-id');
    expect(provider.messages.last.content, 'Completed reply');
  });
}
