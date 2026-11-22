import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';

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

  test('every literal key the app translates exists in en.json', () {
    final english = _english();
    final usage = RegExp(
      r"(?:'([A-Za-z]\w*(?:\.\w+)+)'\s*\.\s*(?:tr|plural)\(|UiText\.key\(\s*'([\w.]+)')",
    );
    final missing = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final match in usage.allMatches(lines[i])) {
          final key = match.group(1) ?? match.group(2)!;
          final isPluralGroup = english.keys.any((k) => k.startsWith('$key.'));
          if (!english.containsKey(key) && !isPluralGroup) {
            missing.add('${file.path}:${i + 1} $key');
          }
        }
      }
    }
    expect(missing, isEmpty, reason: 'keys missing from en.json');
  });

  test('keys built at runtime exist for every value they are built from', () {
    final english = _english();
    final expected = [
      for (final type in GameType.values) ...[
        'games.type.${type.name}.name',
        'games.type.${type.name}.description',
      ],
      for (final days in [7, 14, 30, 60, 100, 365])
        'progress.streakMilestoneMsg.d$days',
      for (final rank in [
        'bronze',
        'silver',
        'gold',
        'platinum',
        'sapphire',
        'ruby',
        'amethyst',
        'master',
        'diamond',
      ])
        'leaderboard.rank.$rank',
      for (final topic in BookProvider.kTopics) 'books.topic.${_camel(topic)}',
    ];
    expect(expected.where((key) => !english.containsKey(key)), isEmpty);
  });
}

Map<String, String> _english() => _flatten(
  jsonDecode(File('assets/i18n/en.json').readAsStringSync())
      as Map<String, dynamic>,
);

String _camel(String words) {
  final parts = words.toLowerCase().split(' ');
  return parts.first +
      parts.skip(1).map((w) => w[0].toUpperCase() + w.substring(1)).join();
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
