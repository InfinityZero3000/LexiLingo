import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/l10n/cached_translation_loader.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/widgets/locale_refresher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tables = {
  'en': {'greeting': 'Hello', 'failed': 'Load failed'},
  'vi': {'greeting': 'Xin chào', 'failed': 'Tải thất bại'},
};

class _MemoryLoader extends AssetLoader {
  const _MemoryLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      _tables[locale.languageCode];
}

/// Stands in for a provider that set its error before the language changed.
class _Holder {
  UiText? stored;
  String? translatedAtStore;
}

Widget _app(_Holder holder) => EasyLocalization(
  supportedLocales: const [Locale('en'), Locale('vi')],
  path: 'unused',
  fallbackLocale: const Locale('en'),
  startLocale: const Locale('en'),
  useOnlyLangCode: true,
  saveLocale: false,
  assetLoader: const _MemoryLoader(),
  child: Builder(
    builder: (context) => MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      builder: (context, child) => LocaleRefresher(child: child!),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              Text('live:${holder.stored?.resolve()}'),
              Text('frozen:${holder.translatedAtStore}'),
              TextButton(
                onPressed: () => context.setLocale(const Locale('vi')),
                child: const Text('switch'),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

void _mockAssets(Map<String, int> hits, {Set<String> failOnce = const {}}) {
  final failed = <String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        hits[key] = (hits[key] ?? 0) + 1;
        if (failOnce.contains(key) && failed.add(key)) return null;
        final code = key.split('/').last.split('.').first;
        final bytes = utf8.encode(json.encode(_tables[code]));
        return ByteData.sublistView(Uint8List.fromList(bytes));
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('stored UiText follows a language switch without a reload', (
    tester,
  ) async {
    final holder = _Holder();
    await tester.pumpWidget(_app(holder));
    await tester.pumpAndSettle();

    holder
      ..stored = const UiText.key('failed')
      ..translatedAtStore = 'failed'.tr();

    await tester.tap(find.text('switch'));
    await tester.pumpAndSettle();

    expect(find.text('live:Tải thất bại'), findsOneWidget);
    // The pattern UiText replaces: translated once, stuck in the old language.
    expect(find.text('frozen:Load failed'), findsOneWidget);
  });

  test('UiText.raw is never translated', () {
    expect(const UiText.raw('greeting').resolve(), 'greeting');
  });

  group('CachedTranslationLoader', () {
    setUp(CachedTranslationLoader.debugClear);
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null),
    );

    test('reads each table once however often a locale is loaded', () async {
      final hits = <String, int>{};
      _mockAssets(hits);
      const loader = CachedTranslationLoader();

      for (var i = 0; i < 3; i++) {
        expect(
          await loader.load('assets/i18n', const Locale('vi')),
          _tables['vi'],
        );
      }
      expect(hits, {'assets/i18n/vi.json': 1});
    });

    test('preload warms every locale before it is requested', () async {
      final hits = <String, int>{};
      _mockAssets(hits);

      await CachedTranslationLoader.preload('assets/i18n', const [
        Locale('en'),
        Locale('vi'),
      ]);
      await const CachedTranslationLoader().load(
        'assets/i18n',
        const Locale('en'),
      );

      expect(hits, {'assets/i18n/en.json': 1, 'assets/i18n/vi.json': 1});
    });

    test('a failed read is retried instead of cached', () async {
      final hits = <String, int>{};
      _mockAssets(hits, failOnce: {'assets/i18n/en.json'});
      const loader = CachedTranslationLoader();

      await expectLater(
        loader.load('assets/i18n', const Locale('en')),
        throwsA(anything),
      );
      expect(
        await loader.load('assets/i18n', const Locale('en')),
        _tables['en'],
      );
      expect(hits['assets/i18n/en.json'], 2);
    });
  });
}
