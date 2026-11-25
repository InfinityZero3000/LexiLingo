import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_surface.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      '${dark ? 'dark' : 'light'}: draws a token-radius framed surface',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: const Scaffold(body: AppSurface(child: Text('hi'))),
          ),
        );
        final box = tester.widget<DecoratedBox>(
          find.byType(DecoratedBox).first,
        );
        final deco = box.decoration as BoxDecoration;
        expect(deco.borderRadius, AppRadius.xlAll);
        expect(deco.border, isNull);
        expect(deco.boxShadow, dark ? isEmpty : isNotEmpty);
      },
    );
  }

  testWidgets('tactile tap calls back and the pressed shadow is shallower', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AppSurface(
            variant: TactileSurfaceVariant.elevated,
            onTap: () => taps++,
            child: const Text('go'),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('go')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final pressed =
        (tester.widget<DecoratedBox>(find.byType(DecoratedBox).first).decoration
                as BoxDecoration)
            .boxShadow!
            .first
            .offset;
    expect(pressed.dy, 1);
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('clean tap calls back', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: AppSurface(onTap: () => taps++, child: const Text('go')),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    expect(taps, 1);
  });
}
