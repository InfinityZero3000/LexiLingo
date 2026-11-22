import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// CJK glyphs come from the platform (Android/iOS system fonts) and from
// CanvasKit's on-demand Noto fallback on web, so no CJK font is bundled.
void main() {
  test('pubspec does not bundle a CJK font', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('NotoSans')));
  });

  test('the theme does not name a bundled CJK family', () {
    final theme = File('lib/core/theme/app_theme.dart').readAsStringSync();
    expect(theme, isNot(contains('NotoSansCJK')));
    expect(theme, isNot(contains('fontFamilyFallback')));
  });
}
