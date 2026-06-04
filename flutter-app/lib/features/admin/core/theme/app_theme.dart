import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onSurface,
        secondary: Color(0xFF2AA7A1),
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        error: AppColors.error,
        onError: Colors.white,
        outline: AppColors.outline,
      ),
      scaffoldBackgroundColor: AppColors.background,
    );

    final spaceGrotesk = GoogleFonts.spaceGroteskTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: spaceGrotesk.copyWith(
        displayLarge: spaceGrotesk.displayLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02,
          color: AppColors.onSurface,
        ),
        headlineLarge: spaceGrotesk.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02,
          fontSize: 32,
          color: AppColors.onSurface,
        ),
        headlineMedium: spaceGrotesk.headlineMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.01,
          fontSize: 24,
          color: AppColors.onSurface,
        ),
        titleLarge: spaceGrotesk.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          color: AppColors.onSurface,
        ),
        titleMedium: spaceGrotesk.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: AppColors.onSurface,
        ),
        bodyLarge: spaceGrotesk.bodyLarge?.copyWith(
          fontSize: 16,
          color: AppColors.onSurface,
        ),
        bodyMedium: spaceGrotesk.bodyMedium?.copyWith(
          fontSize: 14,
          color: AppColors.onSurfaceVariant,
        ),
        labelSmall: spaceGrotesk.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.05,
          fontSize: 11,
          color: AppColors.onSurfaceMuted,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.primary),
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryBright,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.02,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.spaceGrotesk(
          color: AppColors.onSurfaceMuted,
          fontSize: 14,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.outline, width: 0.8),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelStyle: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.outline,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primaryBright,
        unselectedItemColor: AppColors.onSurfaceMuted,
        selectedLabelStyle: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.spaceGrotesk(fontSize: 10),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
