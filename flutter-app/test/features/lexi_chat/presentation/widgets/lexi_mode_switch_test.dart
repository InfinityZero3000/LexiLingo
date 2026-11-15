import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_mode_switch.dart';

void main() {
  testWidgets('200% text in a narrow header: the switch does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Row(
            children: [
              const Icon(Icons.menu),
              Expanded(
                child: LexiModeSwitch(value: LexiMode.chat, onChanged: (_) {}),
              ),
              const Icon(Icons.volume_up),
              const Icon(Icons.add_comment),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(LexiModeSwitch)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('the thumb stretches while it travels and settles at half width', (
    tester,
  ) async {
    Widget host(LexiMode mode) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: LexiModeSwitch(value: mode, onChanged: (_) {}),
          ),
        ),
      ),
    );
    final thumb = find.byKey(const ValueKey('lexi-mode-thumb'));

    await tester.pumpWidget(host(LexiMode.chat));
    final resting = tester.getSize(thumb).width;
    final restingLeft = tester.getTopLeft(thumb).dx;

    await tester.pumpWidget(host(LexiMode.topics));
    await tester.pump(const Duration(milliseconds: 190));
    final mid = tester.getSize(thumb).width;
    final midLeft = tester.getTopLeft(thumb).dx;
    expect(mid, greaterThan(resting));
    expect(midLeft, greaterThan(restingLeft));

    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.getSize(thumb).width, closeTo(resting, 0.5));
    expect(tester.getTopLeft(thumb).dx, greaterThan(midLeft));
  });
}
