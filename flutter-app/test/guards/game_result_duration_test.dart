import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The provider times every game; five of the six result screens used to
/// replace that with a literal 0.
void main() {
  test('no game screen reports a hardcoded zero duration', () {
    final offenders = [
      for (final file in Directory(
        'lib/features/games/presentation/screens',
      ).listSync().whereType<File>())
        if (file.readAsStringSync().contains(RegExp(r'durationSeconds:\s*0,')))
          file.path,
    ];
    expect(offenders, isEmpty);
  });
}
