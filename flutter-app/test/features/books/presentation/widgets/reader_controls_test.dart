import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/widgets/bookmark_button.dart';
import 'package:lexilingo_app/features/books/presentation/widgets/reader_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reads the shipped en.json so a missing key shows up here, not on a device.
class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(File('$path/${locale.languageCode}.json').readAsStringSync())
          as Map<String, dynamic>;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
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
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          home: Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  group('ReaderControls', () {
    ReaderSettings? last;

    Future<void> open(WidgetTester tester, ReaderSettings settings) {
      last = null;
      return _pump(
        tester,
        ReaderControls(settings: settings, onChanged: (s) => last = s),
      );
    }

    testWidgets('labels are localized, not hard-coded English', (tester) async {
      await open(tester, const ReaderSettings());
      expect(find.text('Font size'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Line spacing'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Sepia'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
    });

    testWidgets('picking a theme reports it, keeping the other settings', (
      tester,
    ) async {
      await open(tester, const ReaderSettings(fontSize: 20));
      await tester.tap(find.text('Sepia'));
      expect(last?.theme, ReaderTheme.sepia);
      expect(last?.fontSize, 20);
    });

    testWidgets('theme chips are at least 44px tall to tap', (tester) async {
      await open(tester, const ReaderSettings());
      final chip = find.ancestor(
        of: find.text('Dark'),
        matching: find.byType(AnimatedContainer),
      );
      expect(tester.getSize(chip).height, greaterThanOrEqualTo(44));
    });

    testWidgets('the selected theme is the one the semantics call selected', (
      tester,
    ) async {
      await open(tester, const ReaderSettings(theme: ReaderTheme.dark));
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.text('Dark')),
        matchesSemantics(
          label: 'Dark',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          hasTapAction: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('A+ / A− step the font size by one', (tester) async {
      await open(tester, const ReaderSettings(fontSize: 18));
      await tester.tap(find.byIcon(Icons.text_increase_rounded));
      expect(last?.fontSize, 19);
      await tester.tap(find.byIcon(Icons.text_decrease_rounded));
      expect(last?.fontSize, 17);
    });

    testWidgets('the font size buttons stop at the ends of the range', (
      tester,
    ) async {
      await open(tester, const ReaderSettings(fontSize: 14));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.text_decrease_rounded),
            )
            .onPressed,
        isNull,
      );
      await open(tester, const ReaderSettings(fontSize: 28));
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.text_increase_rounded),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('BookmarkButton', () {
    testWidgets('offers the matching localized action', (tester) async {
      await _pump(tester, BookmarkButton(isBookmarked: false, onToggle: () {}));
      expect(find.byTooltip('Add bookmark'), findsOneWidget);

      await _pump(tester, BookmarkButton(isBookmarked: true, onToggle: () {}));
      expect(find.byTooltip('Remove bookmark'), findsOneWidget);
    });

    testWidgets('tapping reports the toggle', (tester) async {
      var taps = 0;
      await _pump(
        tester,
        BookmarkButton(isBookmarked: false, onToggle: () => taps++),
      );
      await tester.tap(find.byTooltip('Add bookmark'));
      expect(taps, 1);
    });
  });
}
