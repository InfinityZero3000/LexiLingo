import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_memory_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_memory_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

class _Repo implements LexiChatRepository {
  _Repo(this.stored);

  Map<String, String> stored;
  bool failLoad = false;
  bool failForget = false;

  @override
  Future<Map<String, String>> getMemory() async {
    if (failLoad) throw Exception('offline');
    return stored;
  }

  @override
  Future<void> forgetMemory() async {
    if (failForget) throw Exception('500');
    stored = {};
  }

  @override
  Future<void> forgetMemoryFact(String key) async {
    if (failForget) throw Exception('500');
    stored = {...stored}..remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

Future<LexiMemoryProvider> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = LexiMemoryProvider(repository: repo)..load();
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en')],
      path: 'assets/i18n',
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      useOnlyLangCode: true,
      assetLoader: const _DiskAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Scaffold(
            body: ChangeNotifierProvider.value(
              value: provider,
              child: const LexiMemorySheet(),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return provider;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('lists what Lexi remembers with readable labels', (tester) async {
    await _pump(tester, _Repo({'preferred_name': 'Thang', 'goal': 'IELTS'}));

    expect(find.text('What Lexi remembers'), findsOneWidget);
    expect(find.text('Call me'), findsOneWidget);
    expect(find.text('Thang'), findsOneWidget);
    expect(find.text('Learning goal'), findsOneWidget);
    expect(find.text('IELTS'), findsOneWidget);
  });

  testWidgets('forgetting one fact removes just that row', (tester) async {
    await _pump(tester, _Repo({'preferred_name': 'Thang', 'goal': 'IELTS'}));

    await tester.tap(find.byTooltip('Forget this').first);
    await tester.pumpAndSettle();

    expect(find.text('Thang'), findsNothing);
    expect(find.text('IELTS'), findsOneWidget);
  });

  testWidgets('forget everything asks first, then empties the list', (
    tester,
  ) async {
    final repo = _Repo({'goal': 'IELTS'});
    await _pump(tester, repo);

    await tester.tap(find.text('Forget everything'));
    await tester.pumpAndSettle();
    expect(find.text('Forget everything?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.stored, isNotEmpty);

    await tester.tap(find.text('Forget everything'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Forget everything'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.stored, isEmpty);
    expect(find.textContaining('Nothing yet'), findsOneWidget);
  });

  testWidgets('a failed forget keeps the row and says so', (tester) async {
    final repo = _Repo({'goal': 'IELTS'})..failForget = true;
    await _pump(tester, repo);

    await tester.tap(find.byTooltip('Forget this'));
    await tester.pumpAndSettle();

    expect(find.text('IELTS'), findsOneWidget);
    expect(find.text("Couldn't update. Please try again."), findsOneWidget);
  });

  testWidgets('a failed load offers retry instead of looking empty', (
    tester,
  ) async {
    final repo = _Repo({'goal': 'IELTS'})..failLoad = true;
    await _pump(tester, repo);

    expect(find.text("Couldn't load your memory right now."), findsOneWidget);
    expect(find.textContaining('Nothing yet'), findsNothing);

    repo.failLoad = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('IELTS'), findsOneWidget);
  });
}
