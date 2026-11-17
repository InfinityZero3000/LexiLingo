import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Rarity and celebration colours of the achievements module.
abstract final class AchievementPalette {
  static const Color legendary = Color(0xFFFF6B00);
  static const Color cyan = Color(0xFF00BCD4);
  static const Color pink = Color(0xFFE91E63);
  static const Color blue = Color(0xFF2196F3);

  static const List<Color> confetti = [
    AppColors.primary,
    blue,
    pink,
    AppColors.accentYellow,
  ];
}
