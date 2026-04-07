import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color primary = Color(0xFF137FEC);
  static const Color primaryDark = Color(0xFF0D5FC4);
  static const Color backgroundLight = Color(0xFFF6F7F8);
  static const Color backgroundDark = Color(0xFF101922);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1C2A38);
  static const Color surfaceDarkMuted = Color(0xFF1C2632);
  static const Color surfaceDarkElevated = Color(0xFF1C2B3A);
  static const Color textDark = Color(0xFF111418);
  static const Color textInverted = Color(0xFFFFFFFF);
  static const Color textGrey = Color(0xFF617589);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textSlate = Color(0xFF475569);
  static const Color accentYellow = Color(0xFFFFD644);
  static const Color accentMint = Color(0xFF30E8E8);
  static const Color accentMintDark = Color(0xFF112121);
  static const Color greenSuccess = Color(0xFF078838);
  static const Color greenSuccessBright = Color(0xFF4CAF50);
  static const Color greenSuccessSoft = Color(0xFF8BC34A);
  static const Color warning = Color(0xFFFFC107);
  static const Color orange = Color(0xFFFF9800);
  static const Color deepOrange = Color(0xFFFF5722);
  static const Color purple = Color(0xFF9C27B0);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color readingPaper = Color(0xFFF8F5EE);
  static const Color readingSepia = Color(0xFFF4ECD8);
  static const Color readingSepiaAlt = Color(0xFFEDE0CC);
  static const Color readingSepiaText = Color(0xFF4B3B2A);
  static const Color readingNight = Color(0xFF1A1A2E);
  static const Color readingNightAlt = Color(0xFFE8E0D0);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);

  // ── Harmonious gradient pairs ──────────────────────────────────────────────
  // Rule: each pair stays within the same hue family (≤30° apart on color wheel)

  /// Blue → Indigo (primary family, used for Edit Profile, Level badge, headers)
  static const List<Color> primaryGradient = [
    Color(0xFF137FEC),
    Color(0xFF3B5BDB),
  ];

  /// Amber → Deep-Orange (warm, used for XP / Shop actions)
  static const List<Color> warmGradient = [
    Color(0xFFFF9F0A),
    Color(0xFFE05D00),
  ];

  /// Emerald → Teal (green family, used for Ranks / success)
  static const List<Color> successGradient = [
    Color(0xFF10B981),
    Color(0xFF0D9668),
  ];

  /// Violet → Purple (cool-warm, used for Wallet / Gems)
  static const List<Color> purpleGradient = [
    Color(0xFF8B5CF6),
    Color(0xFF7C3AED),
  ];

  /// Indigo → Blue (cool, used for Friends / Social)
  static const List<Color> indigoGradient = [
    Color(0xFF3B82F6),
    Color(0xFF1D4ED8),
  ];

  /// Red → Crimson (danger/delete, kept within red family)
  static const List<Color> dangerGradient = [
    Color(0xFFEF4444),
    Color(0xFFDC2626),
  ];

  /// XP / Achievement gold
  static const List<Color> goldGradient = [
    Color(0xFFFFD644),
    Color(0xFFFF9F0A),
  ];
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.backgroundLight,
      ),
      textTheme: GoogleFonts.lexendTextTheme().apply(
        bodyColor: AppColors.textDark,
        displayColor: AppColors.textDark,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor:
            Colors.transparent, // Or white/transparent based on design
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textDark,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Lexend',
        ),
        iconTheme: IconThemeData(color: AppColors.textDark),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textGrey,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.backgroundDark,
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.lexendTextTheme().apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Lexend',
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1C2A38), // Darker shade for nav bar
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Color(0xFF9CA3AF),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
