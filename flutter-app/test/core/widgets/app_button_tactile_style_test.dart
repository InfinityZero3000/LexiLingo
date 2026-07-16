import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/app_button.dart';

void main() {
  testWidgets('filled and outlined buttons use a strong border', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            AppButton(label: 'Filled'),
            AppButton.outlined(label: 'Outlined'),
            AppButton.ghost(label: 'Ghost'),
          ],
        ),
      ),
    );

    final containers = tester
        .widgetList<Container>(find.byType(Container))
        .where((container) => container.decoration is BoxDecoration)
        .map((container) => container.decoration! as BoxDecoration)
        .toList();

    expect((containers[0].border! as Border).top.width, 2);
    expect((containers[1].border! as Border).top.width, 2);
    expect(containers[2].border, isNull);
  });
}
