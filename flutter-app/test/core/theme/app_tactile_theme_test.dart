import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';

void main() {
  AppTactileTheme theme(Brightness brightness) => AppTactileTheme(
    brightness: brightness,
    primary: const Color(0xFF137FEC),
    onPrimary: Colors.white,
    onSurface: brightness == Brightness.dark ? Colors.white : Colors.black,
    pageBackground: brightness == Brightness.dark
        ? const Color(0xFF151C26)
        : const Color(0xFFF6F7F8),
  );

  test('interactive decoration has canonical border and shadow states', () {
    final resting = theme(Brightness.light).decoration(
      variant: TactileSurfaceVariant.interactive,
      fill: Colors.white,
      accent: const Color(0xFF137FEC),
    );
    final pressed = theme(Brightness.light).decoration(
      variant: TactileSurfaceVariant.interactive,
      fill: Colors.white,
      accent: const Color(0xFF137FEC),
      states: const {WidgetState.pressed},
    );

    expect((resting.border! as Border).top.width, 2);
    expect(resting.borderRadius, BorderRadius.circular(16));
    expect(resting.boxShadow!.single.offset, const Offset(0, 4));
    expect(resting.boxShadow!.single.blurRadius, 0);
    expect(pressed.boxShadow!.single.offset, const Offset(0, 1));
  });

  test('nested and disabled surfaces do not cast a shadow', () {
    final tactile = theme(Brightness.dark);
    final nested = tactile.decoration(
      variant: TactileSurfaceVariant.nested,
      fill: const Color(0xFF243241),
    );
    final disabled = tactile.decoration(
      variant: TactileSurfaceVariant.interactive,
      fill: const Color(0xFF243241),
      states: const {WidgetState.disabled},
    );

    expect((nested.border! as Border).top.width, 1.5);
    expect(nested.boxShadow, isEmpty);
    expect(disabled.boxShadow, isEmpty);
  });

  test('resolved borders meet non-text contrast in both modes', () {
    for (final brightness in Brightness.values) {
      final tactile = theme(brightness);
      final fill = brightness == Brightness.dark
          ? const Color(0xFF243241)
          : Colors.white;
      final decoration = tactile.decoration(
        variant: TactileSurfaceVariant.elevated,
        fill: fill,
        accent: const Color(0xFF137FEC),
      );
      final border = (decoration.border! as Border).top.color;

      expect(
        AppTactileTheme.contrastRatio(border, fill),
        greaterThanOrEqualTo(3),
      );
      expect(
        AppTactileTheme.contrastRatio(border, tactile.pageBackground),
        greaterThanOrEqualTo(3),
      );
    }
  });

  test('impossible contrast tuple fails with actionable diagnostics', () {
    final impossible = AppTactileTheme(
      brightness: Brightness.light,
      primary: const Color(0xFF137FEC),
      onPrimary: Colors.white,
      onSurface: Colors.black,
      pageBackground: Colors.white,
    );

    expect(
      () => impossible.decoration(
        variant: TactileSurfaceVariant.elevated,
        fill: Colors.black,
        diagnosticId: 'impossible-probe',
      ),
      throwsA(
        isA<ArgumentError>().having(
          (error) => error.message.toString(),
          'message',
          allOf(
            contains('impossible-probe'),
            contains('Color('),
            contains('against fill'),
            contains('against page'),
          ),
        ),
      ),
    );
  });

  testWidgets('LearnerTheme scopes Material component styles', (tester) async {
    ThemeData? scoped;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: LearnerTheme(
          child: Builder(
            builder: (context) {
              scoped = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    expect(scoped!.extension<AppTactileTheme>(), isNotNull);
    expect(scoped!.outlinedButtonTheme.style, isNotNull);
    expect(scoped!.cardTheme.elevation, 3);
  });

  test('button disabled and focused states resolve in both modes', () {
    for (final brightness in Brightness.values) {
      final tactile = theme(brightness);
      final disabled = tactile.filledButtonStyle();
      final focused = tactile.textButtonStyle();

      expect(disabled.elevation!.resolve(const {WidgetState.disabled}), 0);
      expect(
        disabled.side!.resolve(const {WidgetState.disabled})!.color,
        tactile.onSurface.withValues(alpha: 0.12),
      );
      expect(focused.side!.resolve(const {WidgetState.focused})!.width, 2);
      expect(
        focused.overlayColor!.resolve(const {WidgetState.focused}),
        tactile.primary.withValues(alpha: 0.12),
      );
      expect(focused.side!.resolve(const {}), BorderSide.none);
    }
  });

  test('copyWith and lerp preserve extension values', () {
    final light = theme(Brightness.light);
    final dark = theme(Brightness.dark);

    expect(light.copyWith().primary, light.primary);
    expect(light.lerp(dark, 1).brightness, Brightness.dark);
    expect(light.lerp(dark, 1).pageBackground, dark.pageBackground);
  });
}
