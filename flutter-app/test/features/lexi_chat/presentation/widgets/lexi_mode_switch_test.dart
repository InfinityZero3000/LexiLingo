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
}
