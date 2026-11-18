import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
