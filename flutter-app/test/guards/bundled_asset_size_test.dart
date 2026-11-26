import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A bundled image is a download on the web and decoded memory everywhere.
/// 1024px badges shown at 64dp once made the profile fetch 18MB.
const _limits = {'assets/badges/': 120 * 1024};
const _defaultLimit = 400 * 1024;

/// Over the limit, with why that is acceptable today. No screen loads these,
/// so they cost app size only; showing one means shrinking it first.
const _allowed = {
  'assets/logo/logo.png': 'brand master, not referenced by the app',
  'assets/logo/logo_1.png': 'launcher icon source, read at build time',
  'assets/background-roadmap/background.png': 'not referenced by the app',
  'assets/out-app/banner-start-lexilingo.png': 'not referenced by the app',
};

void main() {
  final dirs = RegExp(
    r'^\s+- ((?:assets|animation)/\S*/)$',
    multiLine: true,
  ).allMatches(File('pubspec.yaml').readAsStringSync()).map((m) => m.group(1)!);

  test('bundled assets stay small enough to download on the web', () {
    expect(dirs, contains('assets/badges/'));
    final heavy = <String>[];
    for (final dir in dirs) {
      for (final file in Directory(dir).listSync().whereType<File>()) {
        final limit = _limits[dir] ?? _defaultLimit;
        if (file.lengthSync() > limit && !_allowed.containsKey(file.path)) {
          heavy.add('${file.path}: ${file.lengthSync() ~/ 1024}KB');
        }
      }
    }

    expect(heavy, isEmpty, reason: 'resize to the shown size, or use WebP');
  });
}
