import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Decorative colours of shop, wallet and league screens; neutrals come from the theme.
abstract final class RewardPalette {
  static const Color shopPink = Color(0xFFEC4899);
  static const Color starterIndigo = Color(0xFF5552CF);
  static const Color starterIndigoSoft = Color(0xFF7669F7);
  static const Color nightTop = Color(0xFF0B0E14);
  static const Color nightBottom = Color(0xFF05070A);

  static const List<Color> starterGradient = [
    AppColors.accentMint,
    starterIndigoSoft,
  ];
  static const List<Color> walletGradient = [
    Color(0xFF6D28D9),
    Color(0xFF8B5CF6),
    Color(0xFFA78BFA),
  ];
}
