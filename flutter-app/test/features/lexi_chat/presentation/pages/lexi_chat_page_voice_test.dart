import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/backend_auth_header_provider.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_client.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_phase.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

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

class _Settings extends ChangeNotifier implements SettingsProvider {
  @override
  bool get soundEnabled => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repo implements LexiChatRepository {
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

class _FakeVoice extends DuplexVoiceClient {
  _FakeVoice() : super(authHeaders: _Auth(), recorder: _Recorder());

  final startArgs = <Map<String, Object?>>[];
  int stops = 0;
  int interrupts = 0;
  int replays = 0;
  bool replayable = false;
  DuplexVoicePhase? phaseOnStart = DuplexVoicePhase.connecting;
  Object? startError;

  @override
  bool get canReplay => replayable;

  @override
  Future<void> start({
    required String sessionId,
    String learnerLevel = 'B1',
    String nativeLanguage = 'vi',
    double ttsSpeed = 1.0,
  }) async {
    startArgs.add({
      'session': sessionId,
      'level': learnerLevel,
      'speed': ttsSpeed,
    });
    if (phaseOnStart != null) phase.value = phaseOnStart!;
    if (startError != null) throw startError!;
  }

  @override
  Future<void> stop({bool failed = false}) async {
    stops++;
    if (!failed && phase.value != DuplexVoicePhase.unavailable) {
      phase.value = DuplexVoicePhase.idle;
    }
  }

  @override
  Future<void> interrupt() async {
    interrupts++;
    phase.value = DuplexVoicePhase.listening;
  }

  @override
  Future<void> replayLast() async => replays++;

  void emit(Map<String, dynamic> event) {
    phase.value = reduceVoicePhase(phase.value, event);
    events.add(event);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVoice voice;
  late LexiChatProvider chat;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(
      envString: 'ENVIRONMENT=development\nVOICE_DUPLEX_ENABLED=true',
    );
    DuplexVoiceClient.serverUnavailable = false;
    voice = _FakeVoice();
    if (sl.isRegistered<DuplexVoiceClient>()) {
      sl.unregister<DuplexVoiceClient>();
    }
    sl.registerFactory<DuplexVoiceClient>(() => voice);
    chat = LexiChatProvider(repository: _Repo(), aiClient: AiApiClient())
      ..setNativeLanguage('en');
  });

  tearDown(() {
    sl.unregister<DuplexVoiceClient>();
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
    DuplexVoiceClient.serverUnavailable = false;
    chat.dispose();
  });

  void pageTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  Future<void> pumpPage(WidgetTester tester, {bool active = true}) async {
    tester.view.physicalSize = const Size(390, 844);
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
            ],
            child: MaterialApp(
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              home: LexiChatPage(isActive: active),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> startVoice(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await settle(tester);
  }

  Future<void> say(
    WidgetTester tester,
    Map<String, dynamic> event, [
    Duration settle = const Duration(milliseconds: 50),
  ]) async {
    voice.emit(event);
    await tester.pump(settle);
  }

  Future<void> goLive(WidgetTester tester) async {
    await startVoice(tester);
    await say(tester, {'type': 'session_started'});
  }

  pageTest('tapping the mic shows the connecting panel at once', (
    tester,
  ) async {
    await pumpPage(tester);
    expect(find.byType(TextField), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();

    expect(find.text('Connecting…'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  pageTest('goes live: listening, live caption, user and Lexi bubbles', (
    tester,
  ) async {
    await pumpPage(tester);
    await goLive(tester);
    expect(voice.startArgs.single['session'], 's-1');
    expect(find.text('Listening… just start talking'), findsOneWidget);

    await say(tester, {'type': 'stt.partial', 'text': 'what is the past'});
    expect(find.text('Hearing you…'), findsOneWidget);
    expect(find.text('what is the past'), findsOneWidget);

    await say(tester, {
      'type': 'stt.final',
      'turn_id': 't1',
      'text': 'What is the past tense of go?',
    });
    expect(find.text('Lexi is thinking…'), findsOneWidget);
    expect(find.text('what is the past'), findsNothing);
    expect(find.text('What is the past tense of go?'), findsOneWidget);

    await say(tester, {'type': 'llm.token', 'turn_id': 't1', 'text': 'Went.'});
    await say(tester, {'type': 'tts.audio.start', 'turn_id': 't1'});
    expect(find.textContaining('Lexi is speaking'), findsOneWidget);

    await say(tester, {'type': 'turn.done', 'turn_id': 't1'});
    expect(find.text('Listening… just start talking'), findsOneWidget);
    expect(chat.isSending, isFalse);
  });

  pageTest('the orb interrupts Lexi only while she thinks or speaks', (
    tester,
  ) async {
    await pumpPage(tester);
    await goLive(tester);

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();
    expect(voice.interrupts, 0);

    await say(tester, {'type': 'stt.final', 'turn_id': 't1', 'text': 'Hi'});
    await say(tester, {'type': 'tts.audio.start', 'turn_id': 't1'});
    await tester.tap(find.byIcon(Icons.stop_rounded));
    await tester.pump();

    expect(voice.interrupts, 1);
    expect(find.text('Listening… just start talking'), findsOneWidget);
  });

  pageTest('ending the session restores the text input', (tester) async {
    await pumpPage(tester);
    await goLive(tester);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await tester.pump(const Duration(milliseconds: 100));

    expect(voice.stops, greaterThanOrEqualTo(1));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsNothing);
  });

  pageTest('ending the session while Lexi is mid-turn unlocks the chat', (
    tester,
  ) async {
    await pumpPage(tester);
    await goLive(tester);
    await say(tester, {'type': 'stt.final', 'turn_id': 't1', 'text': 'Hi'});
    await say(tester, {'type': 'llm.token', 'turn_id': 't1', 'text': 'Hel'});
    expect(chat.isSending, isTrue);

    await tester.tap(find.byIcon(Icons.call_end_rounded));
    await settle(tester);

    expect(chat.isSending, isFalse);
    expect(find.byType(TextField), findsOneWidget);
  });

  pageTest('a fatal error shows its cause and the orb retries', (tester) async {
    await pumpPage(tester);
    await goLive(tester);

    voice.lastErrorCode = 'QUOTA_EXCEEDED';
    await say(tester, {'type': 'voice.error', 'code': 'QUOTA_EXCEEDED'});

    expect(find.text('Voice chat stopped'), findsOneWidget);
    expect(find.textContaining("used today's voice turns"), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await settle(tester);
    expect(voice.startArgs, hasLength(2));
  });

  pageTest('a busy server is recoverable and keeps the session', (
    tester,
  ) async {
    await pumpPage(tester);
    await goLive(tester);
    await say(tester, {'type': 'stt.final', 'turn_id': 't1', 'text': 'Hi'});

    await say(tester, {
      'type': 'voice.error',
      'code': 'SERVER_BUSY',
      'turn_id': 't1',
    });

    expect(find.text('Listening… just start talking'), findsOneWidget);
    expect(find.textContaining('voice is busy'), findsOneWidget);
    expect(chat.isSending, isFalse);
  });

  pageTest('a server with voice off falls back to the legacy recorder', (
    tester,
  ) async {
    voice
      ..phaseOnStart = null
      ..startError = StateError('404');
    voice.startArgs.clear();
    await pumpPage(tester);

    voice.phase.value = DuplexVoicePhase.unavailable;
    DuplexVoiceClient.serverUnavailable = true;
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.textContaining("isn't available"), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.closed_caption_rounded), findsNothing);
  });

  pageTest('a mis-heard turn offers the transcript for editing', (
    tester,
  ) async {
    await pumpPage(tester);
    await goLive(tester);
    await say(tester, {
      'type': 'stt.final',
      'turn_id': 't1',
      'text': 'I goed there',
      'uncertain': true,
    });

    expect(find.text('Lexi may have misheard — edit'), findsOneWidget);
    await tester.tap(find.text('Lexi may have misheard — edit'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(voice.stops, greaterThanOrEqualTo(1));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'I goed there');
    expect(chat.isSending, isFalse);
  });

  pageTest('captions off covers Lexi\'s voice replies until tapped', (
    tester,
  ) async {
    await pumpPage(tester);
    await goLive(tester);
    await say(tester, {'type': 'stt.final', 'turn_id': 't1', 'text': 'Hi'});
    await say(tester, {
      'type': 'llm.token',
      'turn_id': 't1',
      'text': 'Hello friend',
    });
    await say(tester, {'type': 'turn.done', 'turn_id': 't1'});
    expect(find.text('Hello friend'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.closed_caption_rounded));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hello friend'), findsNothing);
    expect(find.text('Tap to show what Lexi said'), findsOneWidget);

    await tester.tap(find.text('Tap to show what Lexi said'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Hello friend'), findsOneWidget);
  });

  pageTest('replay is only offered when there is something to replay', (
    tester,
  ) async {
    await pumpPage(tester);
    await goLive(tester);
    var replay = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.replay_rounded),
    );
    expect(replay.onPressed, isNull);

    voice.replayable = true;
    voice.phase.value = DuplexVoicePhase.hearing;
    await tester.pump();
    voice.phase.value = DuplexVoicePhase.listening;
    await tester.pump();
    replay = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.replay_rounded),
    );
    await tester.tap(find.byIcon(Icons.replay_rounded));
    expect(voice.replays, 1);
  });

  pageTest('backgrounding the app ends the voice session', (tester) async {
    await pumpPage(tester);
    await goLive(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(milliseconds: 100));

    expect(voice.stops, greaterThanOrEqualTo(1));
    expect(find.byIcon(Icons.call_end_rounded), findsNothing);
  });

  pageTest('switching to another tab ends the voice session', (tester) async {
    await pumpPage(tester);
    await goLive(tester);

    await pumpPage(tester, active: false);
    await tester.pump(const Duration(milliseconds: 100));

    expect(voice.stops, greaterThanOrEqualTo(1));
  });

  pageTest('without the flag there is no duplex UI at all', (tester) async {
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
    await pumpPage(tester);

    expect(find.byIcon(Icons.closed_caption_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(voice.startArgs, isEmpty);
  });
}
