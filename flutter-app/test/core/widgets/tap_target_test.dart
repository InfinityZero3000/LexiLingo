import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_mode_switch.dart';

Future<void> _pumpAt(WidgetTester tester, double width, Widget child) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  for (final width in [390.0, 768.0]) {
    testWidgets('a 20 px icon takes taps over 44 px at $width', (tester) async {
      var taps = 0;
      await _pumpAt(
        tester,
        width,
        TapTarget(
          onTap: () => taps++,
          child: const Icon(Icons.close, size: 20),
        ),
      );

      expect(tester.getSize(find.byType(TapTargetBox)), const Size(44, 44));
      // Two pixels inside the padded corner, well outside the drawn icon.
      await tester.tapAt(
        tester.getTopLeft(find.byType(TapTargetBox)) + const Offset(2, 2),
      );
      expect(taps, 1);
    });
  }

  testWidgets('the desktop layout keeps the drawn size', (tester) async {
    await _pumpAt(
      tester,
      1440,
      TapTarget(onTap: () {}, child: const Icon(Icons.close, size: 20)),
    );
    expect(tester.getSize(find.byType(TapTargetBox)), const Size(20, 20));
  });

  testWidgets('both halves of the Lexi switch are finger-sized on a phone', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    LexiMode? picked;
    await _pumpAt(
      tester,
      390,
      SizedBox(
        width: 220,
        child: LexiModeSwitch(
          value: LexiMode.chat,
          onChanged: (mode) => picked = mode,
        ),
      ),
    );

    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    // The bottom edge used to fall outside the segment.
    final box = tester.getRect(find.byType(LexiModeSwitch));
    await tester.tapAt(Offset(box.right - 30, box.bottom - 1));
    expect(picked, LexiMode.topics);
    handle.dispose();
  });

  testWidgets('the reading column narrows on a tablet only', (tester) async {
    Future<double> columnAt(double width) async {
      await _pumpAt(
        tester,
        width,
        const ContentWidth(
          maxWidth: ContentWidth.reading,
          child: SizedBox(
            key: Key('column'),
            width: double.infinity,
            height: 10,
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('column'))).width;
    }

    expect(await columnAt(390), 390);
    expect(await columnAt(768), 640);
    expect(await columnAt(1440), 760);
  });
}
