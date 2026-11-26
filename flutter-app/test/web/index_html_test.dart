import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web shell turns off the browser tap highlight', () {
    final html = File('web/index.html').readAsStringSync();

    expect(
      html,
      matches(
        RegExp(r'html\s*\{\s*-webkit-tap-highlight-color:\s*transparent;'),
      ),
      reason:
          'Without it Chrome paints a blue veil over the full-page flutter-view',
    );
  });
}
