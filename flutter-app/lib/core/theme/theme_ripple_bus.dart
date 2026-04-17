import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class ThemeRippleEvent {
  final Offset origin;
  final Color color;

  const ThemeRippleEvent({required this.origin, required this.color});
}

class ThemeRippleBus {
  ThemeRippleBus._();

  static final ThemeRippleBus instance = ThemeRippleBus._();

  final ValueNotifier<ThemeRippleEvent?> notifier =
      ValueNotifier<ThemeRippleEvent?>(null);

  void emit({required Offset origin, required String themeCode}) {
    notifier.value = ThemeRippleEvent(
      origin: origin,
      color: _rippleColorForTheme(themeCode),
    );
  }

  Color _rippleColorForTheme(String themeCode) {
    switch (themeCode) {
      case 'dark':
        return AppColors.primaryDarkMode;
      case 'light':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }
}
