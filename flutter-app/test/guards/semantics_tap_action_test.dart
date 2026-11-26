import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `Semantics(excludeSemantics: true)` removes the child's tap action along
/// with its labels. Without its own `onTap` the node is announced as a button
/// that a screen reader (or the web semantics layer) cannot press.
void main() {
  test('no pressable widget hides its tap behind excludeSemantics', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      for (final match in RegExp(r'\bSemantics\(').allMatches(source)) {
        var depth = 1;
        var end = match.end;
        while (end < source.length && depth > 0) {
          if (source[end] == '(') depth++;
          if (source[end] == ')') depth--;
          end++;
        }
        final block = source.substring(match.start, end);
        final own = block.split('child:').first;
        if (own.contains('excludeSemantics: true') &&
            !own.contains('onTap:') &&
            RegExp(r'\b(onTap|onPressed):').hasMatch(block)) {
          final line = '\n'
                  .allMatches(source.substring(0, match.start))
                  .length +
              1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
