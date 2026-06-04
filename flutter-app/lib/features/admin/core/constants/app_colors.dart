import 'package:flutter/material.dart';

class AppColors {
  // Primary orange brand — matches web admin --accent #ff4d00
  static const Color primary = Color(0xFFCC3D00);
  static const Color primaryBright = Color(0xFFFF4D00);
  static const Color primaryContainer = Color(0xFFFFE0D0);
  static const Color primaryLight = Color(0xFFFF9F2D);

  // Backgrounds — matches web admin blue palette
  static const Color background = Color(0xFFE1F2FF);  // --bg
  static const Color surface = Color(0xFFFFFFFF);      // --panel
  static const Color surfaceDim = Color(0xFFCDE8FF);   // --panel-soft
  static const Color surfaceContainerLow = Color(0xFFEDF6FF);  // --panel-soft-2
  static const Color surfaceContainerHigh = Color(0xFFB8D9F5); // --line

  // Text — dark navy matching web admin
  static const Color onSurface = Color(0xFF0D1F2D);       // --panel-ink
  static const Color onSurfaceVariant = Color(0xFF1A2835); // --text
  static const Color onSurfaceMuted = Color(0xFF4A6070);   // --muted

  // Semantic
  static const Color success = Color(0xFF2AA7A1);
  static const Color successContainer = Color(0xFFD4EDEA);
  static const Color warning = Color(0xFFB45309);
  static const Color warningContainer = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);

  // Navy (sidebar / dark cards)
  static const Color navy = Color(0xFF0A192F);
  static const Color navyLight = Color(0xFF213145);

  // Outline — blue lines matching web admin
  static const Color outline = Color(0xFFB8D9F5);    // --line
  static const Color outlineVariant = Color(0xFF9DC2E2); // --line-strong
}
