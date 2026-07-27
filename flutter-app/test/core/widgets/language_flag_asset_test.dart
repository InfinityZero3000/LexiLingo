import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';
import 'package:lexilingo_app/core/widgets/language_flag.dart';

void main() {
  test('every supported locale has a bundled flag', () {
    for (final locale in AppLocales.supportedLocales) {
      expect(
        File(AppLocales.flagAssetOf(locale.languageCode)).existsSync(),
        isTrue,
      );
    }
  });

  testWidgets('shows fallback when a flag asset is missing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LanguageFlag(
          languageCode: 'en',
          width: 24,
          height: 16,
          assetPath: 'assets/flags/missing.png',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
  });
}
