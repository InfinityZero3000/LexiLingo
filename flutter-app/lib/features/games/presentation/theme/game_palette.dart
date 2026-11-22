import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Decorative colours of the games module; neutrals and status colours come from the theme.
abstract final class GamePalette {
  static const Color skyBlue = Color(0xFF38B2FF);
  static const Color skyBlueSoft = Color(0xFF5B9BF5);
  static const Color confettiPink = Color(0xFFE91E63);
  static const Color goldOnLight = Color(0xFF9A7A00);

  static const List<Color> skyGradient = [AppColors.primary, skyBlue];
  static const List<Color> skySoftGradient = [AppColors.primary, skyBlueSoft];

  static const List<Color> fillBlankGradient = [
    Color(0xFF078838),
    Color(0xFF34C25A),
  ];
  static const List<Color> matchingGradient = [
    AppColors.purple,
    Color(0xFFCE93D8),
  ];
  static const List<Color> spellingBeeGradient = [
    Color(0xFFF57C00),
    Color(0xFFFFB74D),
  ];
  static const List<Color> grammarQuizGradient = [
    Color(0xFF0288D1),
    Color(0xFF4FC3F7),
  ];
  static const List<Color> hangmanGradient = [
    AppColors.errorDark,
    Color(0xFFEF9A9A),
  ];
}
