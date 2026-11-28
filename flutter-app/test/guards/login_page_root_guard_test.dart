import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A LoginPage built anywhere but in AuthWrapper has nothing watching for the
/// sign-in: the learner signs in and stays on the form, and the per-account
/// reset that AuthWrapper hosts is gone. Use `openLogin` instead.
void main() {
  test('only AuthWrapper builds the login page', () {
    final builders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('login_page.dart'))
        .where((f) => RegExp(r'\bLoginPage\(').hasMatch(f.readAsStringSync()))
        .map((f) => f.uri.pathSegments.last)
        .toList();

    expect(builders, ['auth_wrapper.dart']);
  });
}
