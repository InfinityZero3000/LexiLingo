import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('i18n asset files keep matching keys and placeholders', () {
    const locales = ['en', 'vi', 'ja', 'ko', 'zh', 'fr', 'es'];

    final translations = <String, Map<String, String>>{};
    for (final locale in locales) {
      final file = File('assets/i18n/$locale.json');
      expect(file.existsSync(), isTrue, reason: '$locale.json is missing');

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      translations[locale] = _flatten(json);
    }

    final english = translations['en']!;
    final englishKeys = english.keys.toSet();
    for (final entry in translations.entries) {
      expect(
        entry.value.keys.toSet(),
        englishKeys,
        reason: '${entry.key}.json must match en.json keys',
      );

      for (final key in englishKeys) {
        expect(
          _placeholders(entry.value[key]!),
          _placeholders(english[key]!),
          reason: '${entry.key}.$key placeholders must match en.$key',
        );
      }
    }
  });
}

Map<String, String> _flatten(Map<String, dynamic> json, [String prefix = '']) {
  final result = <String, String>{};
  for (final entry in json.entries) {
    final key = prefix.isEmpty ? entry.key : '$prefix.${entry.key}';
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      result.addAll(_flatten(value, key));
    } else {
      result[key] = value.toString();
    }
  }
  return result;
}

Set<String> _placeholders(String value) {
  return RegExp(
    r'\{[A-Za-z0-9_]+\}',
  ).allMatches(value).map((match) => match.group(0)!).toSet();
}
