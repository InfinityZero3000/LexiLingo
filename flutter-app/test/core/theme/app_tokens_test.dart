import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('both themes carry status colours', (tester) async {
    expect(AppTheme.lightTheme.extension<AppStatusColors>(), isNotNull);
    expect(AppTheme.darkTheme.extension<AppStatusColors>(), isNotNull);
  });

  test('spacing and radius follow the 4/8 scale', () {
    for (final v in [
      AppSpacing.xs,
      AppSpacing.sm,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xl,
      AppSpacing.xxl,
      AppRadius.sm,
      AppRadius.md,
      AppRadius.lg,
      AppRadius.xl,
    ]) {
      expect(v % 4, 0);
    }
  });

  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  test('status text pairs meet 4.5:1', () {
    for (final s in [AppStatusColors.light, AppStatusColors.dark]) {
      expect(
        contrast(s.onSuccessContainer, s.successContainer),
        ge(4.5),
        reason: 'successContainer',
      );
      expect(
        contrast(s.onWarningContainer, s.warningContainer),
        ge(4.5),
        reason: 'warningContainer',
      );
      expect(contrast(s.onSuccess, s.success), ge(4.5), reason: 'success');
      expect(contrast(s.onWarning, s.warning), ge(4.5), reason: 'warning');
    }
  });

  testWidgets('heading roles are 18 and 20', (tester) async {
    final t = AppTheme.lightTheme.textTheme;
    expect(t.sectionTitle!.fontSize, 18);
    expect(t.heading!.fontSize, 20);
  });

  testWidgets('context.status follows the active theme', (tester) async {
    late AppStatusColors got;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (c) {
            got = c.status;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(got.success, AppStatusColors.dark.success);
  });
}

Matcher ge(num n) => greaterThanOrEqualTo(n);
