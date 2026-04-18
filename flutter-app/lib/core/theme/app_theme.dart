import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // ── Brand / Primary ───────────────────────────────────────────────────────
  static const Color primary = Color(0xFF137FEC);
  static const Color primaryDark = Color(0xFF0D5FC4);

  // ── Backgrounds ───────────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF6F7F8);
  static const Color backgroundDark = Color(0xFF151C26);

  // ── Surfaces (cards, sheets, dialogs) ─────────────────────────────────────
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF243241);

  /// Chat / lexi chat input bar, slightly darker than surfaceDark
  static const Color surfaceDarkMuted = Color(0xFF202B37);
  static const Color surfaceDarkElevated = Color(0xFF2A3746);

  /// lexi-chat bubble / input field background (dark) — maps to 0xFF2A3A4A
  static const Color surfaceDarkChat = Color(0xFF324253);

  /// Input fields, text field fill in dark mode
  static const Color surfaceDarkInput = Color(0xFF1A2431);

  /// Deeper chat/overlay surface used for chips and input wells in dark mode
  static const Color surfaceDarkInk = Color(0xFF0A1628);

  /// Dark card tone used by Lexi correction and hint containers
  static const Color surfaceDarkCard = Color(0xFF1A2E3F);

  /// Subtle dark border for elevated dark cards
  static const Color borderDarkSoft = Color(0xFF3A4A5A);

  /// Warm light surfaces used for correction and hint cards
  static const Color surfaceWarm = Color(0xFFFFFBF5);
  static const Color surfaceWarmSoft = Color(0xFFFFF8F0);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const Color textDark = Color(0xFF111418);
  static const Color textInverted = Color(0xFFFFFFFF);
  static const Color textGrey = Color(0xFF617589);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textSlate = Color(0xFF475569);

  /// Lighter slate for secondary labels in dark contexts
  static const Color textSlateLight = Color(0xFF64748B);

  // ── Neutral / Gray scale ──────────────────────────────────────────────────
  static const Color grey50 = Color(0xFFF8F9FA);
  static const Color grey100 = Color(0xFFF1F5F9);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);

  /// Border separators in light mode
  static const Color grey400 = Color(0xFFBDBDBD);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey600 = Color(0xFF757575);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey800 = Color(0xFF424242);

  /// Dark surface for skeleton / input in dark themes
  static const Color grey900 = Color(0xFF212121);

  // ── Status: Success / Green ───────────────────────────────────────────────
  static const Color greenSuccess = Color(0xFF078838);
  static const Color greenSuccessBright = Color(0xFF4CAF50);
  static const Color greenSuccessSoft = Color(0xFF8BC34A);

  /// bg tint for success state chips/banners (light)
  static const Color greenSuccessBg = Color(0xFFE8F5E9);

  /// deep green for text on success bg
  static const Color greenSuccessDark = Color(0xFF1B5E20);

  // ── Status: Warning / Amber ───────────────────────────────────────────────
  static const Color warning = Color(0xFFFFC107);
  static const Color warningDark = Color(0xFFB7860E);

  /// bg tint for warning chips/banners
  static const Color warningBg = Color(0xFFFFF8E1);

  // ── Status: Error / Red ───────────────────────────────────────────────────
  static const Color error = Color(0xFFB00020);
  static const Color errorBright = Color(0xFFEF5350);

  /// bg tint for error chips/banners (light)
  static const Color errorBg = Color(0xFFFFEBEE);

  /// deep red for danger text
  static const Color errorDark = Color(0xFFC62828);

  // ── Accent: Orange / Warm ─────────────────────────────────────────────────
  static const Color orange = Color(0xFFFF9800);
  static const Color deepOrange = Color(0xFFFF5722);

  /// bg tint for streak/XP accent in light mode
  static const Color orangeBg = Color(0xFFFFF3E0);

  // ── Accent: Yellow / Gold ─────────────────────────────────────────────────
  static const Color accentYellow = Color(0xFFFFD644);

  /// Standard gold used in achievement/rank contexts
  static const Color gold = Color(0xFFFFD700);
  static const Color goldDark = Color(0xFFB8720E);

  /// Classic trophy bronze color
  static const Color bronze = Color(0xFFCD7F32);

  /// Classic silver color
  static const Color silver = Color(0xFFC0C0C0);

  // ── Accent: Purple / Violet ───────────────────────────────────────────────
  static const Color purple = Color(0xFF9C27B0);
  static const Color purpleLight = Color(0xFFA855F7);

  // ── Accent: Teal / Mint ───────────────────────────────────────────────────
  static const Color accentMint = Color(0xFF30E8E8);
  static const Color accentMintDark = Color(0xFF112121);
  static const Color teal = Color(0xFF00897B);

  // ── Accent: Cyan glow ─────────────────────────────────────────────────────
  static const Color cyanGlow = Color(0xFF19FCFC);
  static const Color cyanGlowDark = Color(0xFF30E8E8);

  // ── Dark-Mode Accent & Text Roles ─────────────────────────────────────────
  static const Color primaryDarkMode = Color(0xFF19FCFC);
  static const Color primaryDarkModeSoft = Color(0xFF8CFDFF);
  static const Color primaryDarkModeDeep = Color(0xFF0AAEB8);
  static const Color textOnDarkPrimary = Color(0xFFEFFDFF);
  static const Color textOnDarkSecondary = Color(0xFFB8D7DF);
  static const Color textOnDarkMuted = Color(0xFF88A6B0);

  // ── Home Quick Actions (dark mode) ────────────────────────────────────────
  static const List<Color> quickActionDarkPalette = [
    Color(0xFFFF3131),
    Color(0xFFFC1AD3),
    Color(0xFFFFA319),
    Color(0xFF35FF0D),
    Color(0xFFFF8717),
    Color(0xFF8052FF),
    Color(0xFFFF369E),
  ];

  // ── Roadmap accents in dark mode ──────────────────────────────────────────
  static const List<Color> roadmapEarlyStepDarkPalette = [
    Color(0xFF5ED8FF),
    Color(0xFF5BEEB6),
    Color(0xFFFFC46E),
  ];
  static const Color roadmapNodeFallbackDark = Color(0xFF66CFF5);

  // ── Slate / Ink ───────────────────────────────────────────────────────────
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate200 = Color(0xFFE2E8F0);

  // ── Reading mode ──────────────────────────────────────────────────────────
  static const Color readingPaper = Color(0xFFF8F5EE);
  static const Color readingSepia = Color(0xFFF4ECD8);
  static const Color readingSepiaAlt = Color(0xFFEDE0CC);
  static const Color readingSepiaText = Color(0xFF4B3B2A);
  static const Color readingNight = Color(0xFF1A1A2E);
  static const Color readingNightAlt = Color(0xFFE8E0D0);

  // ── Chat specific ─────────────────────────────────────────────────────────
  /// Light mode input / background for chat (maps to 0xFFE8ECEF)
  static const Color chatBgLight = Color(0xFFE8ECEF);

  /// Light mode message list background (maps to 0xFFF6F7F8)
  static const Color chatBgAlt = Color(0xFFF6F7F8);

  // ── Gradient pairs ────────────────────────────────────────────────────────
  // Rule: each pair stays within the same hue family (≤30° apart)

  /// Blue → Indigo (primary family)
  static const List<Color> primaryGradient = [
    Color(0xFF137FEC),
    Color(0xFF3B5BDB),
  ];

  static const List<Color> primaryGradientDark = [
    Color(0xFF19FCFC),
    Color(0xFF0AAEB8),
  ];

  /// Amber → Deep-Orange (warm, used for XP / Shop)
  static const List<Color> warmGradient = [
    Color(0xFFFF9F0A),
    Color(0xFFE05D00),
  ];

  /// Emerald → Teal (green family, used for Ranks / success)
  static const List<Color> successGradient = [
    Color(0xFF10B981),
    Color(0xFF0D9668),
  ];

  /// Violet → Purple (used for Wallet / Gems)
  static const List<Color> purpleGradient = [
    Color(0xFF8B5CF6),
    Color(0xFF7C3AED),
  ];

  /// Indigo → Blue (used for Friends / Social)
  static const List<Color> indigoGradient = [
    Color(0xFF3B82F6),
    Color(0xFF1D4ED8),
  ];

  /// Red → Crimson (danger/delete)
  static const List<Color> dangerGradient = [
    Color(0xFFEF4444),
    Color(0xFFDC2626),
  ];

  /// XP / Achievement gold
  static const List<Color> goldGradient = [
    Color(0xFFFFD644),
    Color(0xFFFF9F0A),
  ];

  /// Streak fire gradient (orange family)
  static const List<Color> streakGradient = [
    Color(0xFFFF9F0A),
    Color(0xFFFF5722),
  ];
}

class AppColorRoles {
  const AppColorRoles._();

  static Color primary(bool isDark) =>
      isDark ? AppColors.primaryDarkMode : AppColors.primary;

  static Color primaryDeep(bool isDark) =>
      isDark ? AppColors.primaryDarkModeDeep : AppColors.primaryDark;

  static List<Color> primaryGradient(bool isDark) =>
      isDark ? AppColors.primaryGradientDark : AppColors.primaryGradient;

  static Color textPrimary(bool isDark) =>
      isDark ? AppColors.textOnDarkPrimary : AppColors.textDark;

  static Color textSecondary(bool isDark) =>
      isDark ? AppColors.textOnDarkSecondary : AppColors.textGrey;

  static Color textMuted(bool isDark) =>
      isDark ? AppColors.textOnDarkMuted : AppColors.textMuted;
}

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.backgroundLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        surface: AppColors.surfaceLight,
        surfaceContainer: AppColors.backgroundLight,
        surfaceContainerHighest: AppColors.grey200,
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
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
        seedColor: AppColors.primaryDarkMode,
        primary: AppColors.primaryDarkMode,
        secondary: AppColors.primaryDarkModeSoft,
        surface: AppColors.surfaceDark,
        surfaceContainer: AppColors.backgroundDark,
        surfaceContainerHighest: AppColors.surfaceDarkMuted,
        brightness: Brightness.dark,
      ),
      textTheme: GoogleFonts.lexendTextTheme().apply(
        bodyColor: AppColors.textOnDarkPrimary,
        displayColor: AppColors.textOnDarkPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: AppColors.textOnDarkPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          fontFamily: 'Lexend',
        ),
        iconTheme: IconThemeData(color: AppColors.textOnDarkPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surfaceDarkMuted,
        selectedItemColor: AppColors.primaryDarkMode,
        unselectedItemColor: AppColors.textOnDarkMuted,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
