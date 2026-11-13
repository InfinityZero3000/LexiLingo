import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_client.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_phase.dart';
import 'package:lexilingo_app/features/chat/domain/entities/story.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/story_repository.dart';
import 'package:lexilingo_app/features/chat/presentation/pages/story_selection_page.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_hub_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth implements BackendAuthHeaderProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Recorder implements AudioRecorder {
  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeVoice extends DuplexVoiceClient {
  _FakeVoice() : super(authHeaders: _Auth(), recorder: _Recorder());

  int stops = 0;

  @override
  Future<void> start({
    required String sessionId,
    String learnerLevel = 'B1',
    String nativeLanguage = 'vi',
    String spokenLanguage = 'auto',
    double ttsSpeed = 1.0,
  }) async {
    phase.value = DuplexVoicePhase.connecting;
  }

  @override
  Future<void> stop({bool failed = false}) async {
    stops++;
    phase.value = DuplexVoicePhase.idle;
  }

  void emit(Map<String, dynamic> event) {
    phase.value = reduceVoicePhase(phase.value, event);
    events.add(event);
  }
}

class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Settings extends ChangeNotifier implements SettingsProvider {
  @override
  bool get soundEnabled => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _LexiRepo implements LexiChatRepository {
  @override
  Future<LexiSession> createSession({required String userId}) async =>
      LexiSession(
        sessionId: 's-1',
        userId: userId,
        createdAt: DateTime.parse('2026-05-30T00:00:00Z'),
        title: 'Lexi Chat',
      );

  @override
  Future<List<LexiSession>> getSessions({required String userId}) async =>
      const [];

  @override
  Future<LexiMessagesPage> getMessagesPaged({
    required String sessionId,
    int limit = 50,
    String? cursor,
  }) async => const LexiMessagesPage(
    messages: [],
    hasMore: false,
    nextCursor: null,
    returned: 0,
  );

  @override
  Future<List<LexiMessage>> getMessages({required String sessionId}) async =>
      const [];

  @override
  Future<Map<String, String>> getMemory() async => const {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StoryRepo implements StoryRepository {
  _StoryRepo(this.stories);

  final List<StoryListItem> stories;

  @override
  Future<Either<Failure, List<StoryListItem>>> getStories({
    String? category,
    DifficultyLevel? difficultyLevel,
    int limit = 100,
  }) async => Right(stories);

  @override
  Future<Either<Failure, List<String>>> getCategories() async =>
      const Right([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _airport = StoryListItem(
  storyId: 's1',
  title: LocalizedTitle(vi: 'Ở sân bay', en: 'At the airport'),
  difficultyLevel: DifficultyLevel.A2,
  category: 'travel',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LexiChatProvider chat;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
    chat = LexiChatProvider(repository: _LexiRepo(), aiClient: AiApiClient())
      ..setNativeLanguage('en');
  });

  tearDown(() => chat.dispose());

  Future<void> pumpHub(
    WidgetTester tester, {
    bool active = true,
    List<StoryListItem> stories = const [_airport],
  }) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/i18n',
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        assetLoader: const _DiskAssetLoader(),
        child: Builder(
          builder: (context) => MultiProvider(
            providers: [
              ChangeNotifierProvider<LexiChatProvider>.value(value: chat),
              ChangeNotifierProvider<SettingsProvider>.value(
                value: _Settings(),
              ),
              ChangeNotifierProvider<StoryProvider>(
                create: (_) => StoryProvider(repository: _StoryRepo(stories)),
              ),
            ],
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: LexiHubPage(isActive: active),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  // The hidden mode sits offstage under the IndexedStack, so finders must
  // not skip it: being there at all is what the tests check.
  final chatPage = find.byType(LexiChatPage, skipOffstage: false);
  final topicsPage = find.byType(StorySelectionPage, skipOffstage: false);

  bool chatActive(WidgetTester tester) =>
      tester.widget<LexiChatPage>(chatPage).isActive;

  // A mode is built on its first frame and loads its data on the next.
  Future<void> settleModes(WidgetTester tester) async {
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Tapped by icon: on a narrow header the switch hides its labels.
  Future<void> switchTo(WidgetTester tester, LexiMode mode) async {
    await tester.tap(
      find.byIcon(switch (mode) {
        LexiMode.chat => PhosphorIconsRegular.sparkle,
        LexiMode.topics => PhosphorIconsRegular.chatCircleDots,
      }),
    );
    await settleModes(tester);
  }

  void hubTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  hubTest('opens on free chat and builds topics only when asked', (
    tester,
  ) async {
    await pumpHub(tester);

    expect(chatPage, findsOneWidget);
    expect(topicsPage, findsNothing);
    expect(chatActive(tester), isTrue);
  });

  hubTest('switching modes keeps both pages alive and silences the chat', (
    tester,
  ) async {
    await pumpHub(tester);
    await tester.enterText(find.byType(TextField).first, 'half a thought');

    await switchTo(tester, LexiMode.topics);

    expect(topicsPage, findsOneWidget);
    expect(find.text('At the airport'), findsOneWidget);
    // Hidden, not disposed: the mic and speaker are told to stop instead.
    expect(chatPage, findsOneWidget);
    expect(chatActive(tester), isFalse);
    expect(chat.audioMuted, isTrue);

    await switchTo(tester, LexiMode.chat);

    expect(chatActive(tester), isTrue);
    expect(chat.audioMuted, isFalse);
    expect(topicsPage, findsOneWidget);
    expect(find.text('half a thought'), findsOneWidget);
  });

  hubTest('a hidden tab deactivates the chat whatever the mode', (
    tester,
  ) async {
    await pumpHub(tester, active: false);
    expect(chatActive(tester), isFalse);
  });

  hubTest('switching to topics ends a live voice call', (tester) async {
    dotenv.loadFromString(
      envString: 'ENVIRONMENT=development\nVOICE_DUPLEX_ENABLED=true',
    );
    DuplexVoiceClient.serverUnavailable = false;
    final voice = _FakeVoice();
    if (sl.isRegistered<DuplexVoiceClient>()) {
      sl.unregister<DuplexVoiceClient>();
    }
    sl.registerFactory<DuplexVoiceClient>(() => voice);
    addTearDown(() {
      sl.unregister<DuplexVoiceClient>();
      dotenv.loadFromString(envString: 'ENVIRONMENT=development');
    });

    await pumpHub(tester);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    voice.emit({'type': 'session_started'});
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);

    await switchTo(tester, LexiMode.topics);

    expect(voice.stops, greaterThanOrEqualTo(1));
    expect(find.byIcon(Icons.call_end_rounded), findsNothing);
  });

  hubTest('with no topics the empty state offers the way back to free chat', (
    tester,
  ) async {
    await pumpHub(tester, stories: const []);
    await switchTo(tester, LexiMode.topics);

    // Nothing to filter, so no search box or level chips.
    expect(find.text('No topics yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Beginner'), findsNothing);

    await tester.tap(find.text('Chat with Lexi'));
    await settleModes(tester);

    expect(chatActive(tester), isTrue);
    expect(find.byType(TextField), findsOneWidget);
  });
}
