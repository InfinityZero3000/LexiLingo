import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/l10n/cached_translation_loader.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/widgets/locale_refresher.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _tables = {
  'en': {'greeting': 'Hello'},
  'vi': {'greeting': 'Xin chào'},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('a rebuild while the table is still loading keeps no old text', (
    tester,
  ) async {
    CachedTranslationLoader.debugClear();
    final vietnamese = Completer<void>();
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (message) async {
        final key = utf8.decode(message!.buffer.asUint8List());
        final code = key.split('/').last.split('.').first;
        if (code == 'vi') await vietnamese.future; // a network fetch on web
        return ByteData.sublistView(
          Uint8List.fromList(utf8.encode(json.encode(_tables[code]))),
        );
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        null,
      );
      CachedTranslationLoader.debugClear();
    });

    // Stands in for SettingsProvider, which rebuilds MaterialApp.
    final rebuild = ValueNotifier(0);
    late BuildContext screen;
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('vi')],
        path: CachedTranslationLoader.translationsPath,
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        useOnlyLangCode: true,
        saveLocale: false,
        assetLoader: const CachedTranslationLoader(),
        child: ValueListenableBuilder(
          valueListenable: rebuild,
          builder: (context, _, _) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            builder: (context, child) => LocaleRefresher(child: child!),
            home: Builder(
              builder: (context) {
                screen = context;
                return Text('greeting'.tr());
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);

    rebuild.value++;
    final switched = LocaleService.updateAppLocale(screen, 'vi');
    await tester.pump();
    vietnamese.complete();
    await switched;
    await tester.pumpAndSettle();

    expect(find.text('Xin chào'), findsOneWidget);
  });
}
