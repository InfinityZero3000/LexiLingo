import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';

void main() {
  Future<double> childWidth(
    WidgetTester tester,
    double surface,
    Widget Function(Widget child) wrap,
  ) async {
    await tester.binding.setSurfaceSize(Size(surface, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const key = Key('child');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: wrap(const SizedBox.expand(key: key)),
      ),
    );
    return tester.getSize(find.byKey(key)).width;
  }

  testWidgets('caps the child on a desktop window', (tester) async {
    expect(
      await childWidth(
        tester,
        1440,
        (c) => ContentWidth(maxWidth: ContentWidth.reading, child: c),
      ),
      ContentWidth.reading,
    );
    expect(
      await childWidth(tester, 1440, (c) => ContentWidth(child: c)),
      ContentWidth.wide,
    );
  });

  testWidgets('leaves a phone layout alone', (tester) async {
    expect(
      await childWidth(
        tester,
        375,
        (c) => ContentWidth(maxWidth: ContentWidth.reading, child: c),
      ),
      375,
    );
  });

  test('adaptiveColumns breakpoints', () {
    expect(adaptiveColumns(679), 2);
    expect(adaptiveColumns(680), 3);
    expect(adaptiveColumns(999), 3);
    expect(adaptiveColumns(1000), 4);
  });
}
