import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

void main() {
  test('uses dark mobile system bars for dark theme', () {
    final style = AppTheme.systemUiOverlayStyle(Brightness.dark);

    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarIconBrightness, Brightness.light);
    expect(style.systemNavigationBarColor, AppColors.backgroundDark);
  });

  test('uses light mobile system bars for light theme', () {
    final style = AppTheme.systemUiOverlayStyle(Brightness.light);

    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    expect(style.systemNavigationBarColor, AppColors.backgroundLight);
  });
}
