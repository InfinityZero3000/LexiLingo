import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _entryPoints = {
  'namedRoute', 'tab', 'imperativeRoute', 'overlay', 'surface',
};
const _categories = {'eligible', 'excluded'};
const _statuses = {'inventoried', 'planned', 'migrated', 'excluded'};
final _argb = RegExp(r'^0x[0-9A-F]{8}$');

void main() {
  test('learner tactile inventory is valid and covers source occurrences', () {
    final root = Directory.current;
    final inventoryFile = File(
      '${root.path}/docs/ui/learner-tactile-style-inventory.json',
    );
    expect(inventoryFile.existsSync(), isTrue, reason: 'inventory is required');
    final document = jsonDecode(inventoryFile.readAsStringSync()) as Map;
    final rows = (document['occurrences'] as List).cast<Map>();
    final boundaries = (document['boundaries'] as List).cast<Map>();
    final ids = <String>{};

    for (final boundary in boundaries) {
      expect(boundary['pattern'], isNotEmpty);
      expect(boundary['scope'], 'excluded');
      expect(boundary['reason'], isNotEmpty);
    }
    expect(
      boundaries.map((row) => row['pattern']),
      containsAll(<String>[
        'lib/features/admin/**',
        'lib/features/profile/presentation/widgets/profile_page/admin_panel_tile.dart',
        'lib/features/auth/**',
        'lib/features/onboarding/**',
        'lib/features/splash/**',
      ]),
    );

    for (final row in rows) {
      final id = '${row['path']}::${row['symbol']}::${row['callKind']}::${row['ordinal']}';
      expect(row['id'], id);
      expect(ids.add(id), isTrue, reason: 'duplicate inventory id: $id');
      expect(_entryPoints, contains(row['entryPoint']));
      expect(_categories, contains(row['category']));
      expect(_statuses, contains(row['status']));
      expect(row['group'], inInclusiveRange(1, 7));
      if (row['category'] == 'excluded') expect(row['reason'], isNotEmpty);
      if (row['entryPoint'] == 'surface') _checkColors(row, id);
    }

    final discovered = _discover(root);
    expect(ids, containsAll(discovered), reason: 'inventory has uncovered source occurrences');
    expect(
      ids,
      containsAll(List.generate(
        5,
        (index) => 'lib/features/home/presentation/pages/main_screen.dart::MainScreen::MainScreenTab::$index',
      )),
      reason: 'all five MainScreen tabs must be explicit',
    );
  });
}

void _checkColors(Map row, String id) {
  final colors = row['colors'] as Map;
  for (final mode in ['light', 'dark']) {
    final tuple = colors[mode] as Map;
    for (final key in ['accent', 'fill', 'pageBackground', 'intermediateFill']) {
      final value = tuple[key];
      expect(value == null || _argb.hasMatch(value as String), isTrue,
          reason: '$id has invalid $mode.$key');
    }
    final accent = tuple['accent'];
    final fill = tuple['fill'];
    final page = tuple['pageBackground'];
    if (accent != null && fill != null && page != null) {
      final intermediate = tuple['intermediateFill'];
      final effectiveFill = intermediate ?? fill;
      expect(
        _contrast(accent as String, effectiveFill as String) >= 3 &&
            _contrast(accent, page as String) >= 3,
        isTrue,
        reason: '$id cannot reach 3:1 in $mode',
      );
    }
  }
}

Set<String> _discover(Directory root) {
  final lib = Directory('${root.path}/lib');
  final result = <String>{};
  final patterns = <(String, String, String)>[
    (r'''['"](/[^'"]+)['"]\s*:''', 'namedRoute', 'namedRoute'),
    (r'Navigator\.pushNamed\s*\(', 'imperativeRoute', 'Navigator.pushNamed'),
    (r'Navigator\.push\s*\(', 'imperativeRoute', 'Navigator.push'),
    (r'MaterialPageRoute\s*\(', 'imperativeRoute', 'MaterialPageRoute'),
    (r'showDialog(?:<[^>]+>)?\s*\(', 'overlay', 'showDialog'),
    (r'showGeneralDialog\s*\(', 'overlay', 'showGeneralDialog'),
    (r'showModalBottomSheet(?:<[^>]+>)?\s*\(', 'overlay', 'showModalBottomSheet'),
    (r'Card\s*\(', 'surface', 'Card'),
    (r'BoxDecoration\s*\(', 'surface', 'BoxDecoration'),
    (r'DecoratedBox\s*\(', 'surface', 'DecoratedBox'),
  ];
  final excluded = [
    'lib/features/admin/',
    'lib/features/auth/',
    'lib/features/onboarding/',
    'lib/features/splash/',
    'lib/features/profile/presentation/widgets/profile_page/admin_panel_tile.dart',
  ];
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final path = file.path.substring(root.path.length + 1);
    if (excluded.any((prefix) => path.startsWith(prefix))) continue;
    final source = file.readAsStringSync();
    for (final pattern in patterns) {
      final ordinals = <String, int>{};
      for (final match in RegExp(pattern.$1).allMatches(source)) {
        final symbol = _enclosingSymbol(source.substring(0, match.start));
        final ordinalKey = '$symbol::${pattern.$3}';
        final ordinal = ordinals.update(ordinalKey, (value) => value + 1, ifAbsent: () => 0);
        result.add('$path::$symbol::${pattern.$3}::$ordinal');
      }
    }
  }
  return result;
}

String _enclosingSymbol(String prefix) {
  final declarations = RegExp(
    r'(?:class|mixin|extension|enum)\s+([A-Za-z_]\w*)',
  ).allMatches(prefix);
  final last = declarations.isEmpty ? null : declarations.last;
  return last?.group(1) ?? '<top-level>';
}

double _contrast(String left, String right) {
  double luminance(String argb) {
    final value = int.parse(argb.substring(2), radix: 16);
    double channel(int shift) {
      final c = ((value >> shift) & 0xff) / 255;
      return c <= .04045 ? c / 12.92 : ((c + .055) / 1.055) * ((c + .055) / 1.055) * ((c + .055) / 1.055);
    }
    return .2126 * channel(16) + .7152 * channel(8) + .0722 * channel(0);
  }
  final a = luminance(left) + .05;
  final b = luminance(right) + .05;
  return a > b ? a / b : b / a;
}
