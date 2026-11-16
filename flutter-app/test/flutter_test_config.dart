// ignore_for_file: implementation_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';

/// `I18N_AUDIT_LOCALE=fr flutter test` renders every widget test with that
/// language's real strings instead of keys, so text that only overflows once
/// translated (French and Vietnamese run long, CJK runs wide) fails a test.
/// Without the variable nothing changes.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final code = Platform.environment['I18N_AUDIT_LOCALE'];
  if (code != null && code.isNotEmpty) {
    Map<String, dynamic> table(String c) =>
        jsonDecode(File('assets/i18n/$c.json').readAsStringSync())
            as Map<String, dynamic>;
    Localization.load(
      Locale(code),
      translations: Translations(table(code)),
      fallbackTranslations: Translations(table('en')),
    );
  }
  await testMain();
}
