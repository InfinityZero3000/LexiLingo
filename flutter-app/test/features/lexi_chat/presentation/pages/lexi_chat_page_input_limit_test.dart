import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/utils/chat_input_limit.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_messages_page.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_session.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dotenv.loadFromString(envString: 'ENVIRONMENT=development');
  });

  testWidgets('the Lexi input cuts a paste at 4000 and shows the counter', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final chat = LexiChatProvider(repository: _Repo(), aiClient: AiApiClient())
      ..setNativeLanguage('en');
    addTearDown(chat.dispose);

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
              home: const LexiChatPage(isActive: true),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final field = find.byType(TextField);
    expect(field, findsOneWidget);
    expect(find.textContaining('/ $kMaxChatMessageChars'), findsNothing);

    await tester.enterText(field, 'a' * 6000);
    await tester.pump();

    expect(
      tester.widget<TextField>(field).controller!.text.length,
      kMaxChatMessageChars,
    );
    expect(
      find.text('$kMaxChatMessageChars / $kMaxChatMessageChars'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
