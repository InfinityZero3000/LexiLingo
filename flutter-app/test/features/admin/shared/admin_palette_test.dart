import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/admin/core/theme/admin_palette.dart';
import 'package:lexilingo_app/features/admin/features/users/data/users_repository.dart';
import 'package:lexilingo_app/features/admin/features/users/presentation/users_screen.dart';

import '../users/admin_screen_host.dart';
import '../users/admin_test_api.dart';

double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Future<AdminPalette> _palette(WidgetTester tester, ThemeData theme) async {
  late AdminPalette p;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          p = context.ac;
          return const SizedBox();
        },
      ),
    ),
  );
  return p;
}

void main() {
  for (final name in const ['light', 'dark']) {
    testWidgets('$name: text and status roles reach 4.5:1', (tester) async {
      final p = await _palette(
        tester,
        name == 'dark' ? AppTheme.darkTheme : AppTheme.lightTheme,
      );
      final grounds = {
        'surface': p.surface,
        'background': p.background,
        'surfaceDim': p.surfaceDim,
        'surfaceContainerLow': p.surfaceContainerLow,
      };
      final texts = {
        'onSurface': p.onSurface,
        'onSurfaceVariant': p.onSurfaceVariant,
        'onSurfaceMuted': p.onSurfaceMuted,
        'error': p.error,
      };
      for (final g in grounds.entries) {
        for (final t in texts.entries) {
          expect(
            contrast(t.value, g.value),
            greaterThanOrEqualTo(4.5),
            reason: '$name: ${t.key} on ${g.key}',
          );
        }
      }
      expect(contrast(p.onSurface, p.errorContainer), greaterThan(4.5));
      expect(contrast(p.onNavy, p.navy), greaterThan(4.5));
      expect(contrast(p.onNavy, p.navyLight), greaterThan(4.5));
      expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(3));
    });
  }

  testWidgets('the users list renders in dark mode without overflow', (
    tester,
  ) async {
    final api = FakeAdminApi((m, p, q) async => (200, {'data': <dynamic>[]}));
    for (final size in const [
      Size(375, 812),
      Size(768, 1024),
      Size(1024, 768),
    ]) {
      await pumpAdminScreen(
        tester,
        UsersScreen(repository: UsersRepository(api: api.client)),
        size: size,
        themeMode: ThemeMode.dark,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'size $size');
    }
  });
}
