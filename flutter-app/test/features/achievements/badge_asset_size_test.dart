import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The profile shows up to ten badges at 64dp; 1024px originals made that
  // an 18MB download.
  test('every bundled badge stays small enough to list on the profile', () {
    final heavy = Directory('assets/badges')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.png') && f.lengthSync() > 120 * 1024)
        .map((f) => f.path)
        .toList();

    expect(heavy, isEmpty, reason: 'resize to 384px and quantize');
  });
}
