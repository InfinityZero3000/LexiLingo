import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Signature LexiLingo Admin orange palette & neutral slate surfaces.
class AdminBrandColors {
  const AdminBrandColors._();

  static const Color orange = Color(0xFFFF4D00);
  static const Color orangeDarkMode = Color(0xFFFF6A1A);
  static const Color orangeSoftLight = Color(0xFFFFF1EB);
  static const Color orangeSoftDark = Color(0xFF2D1B12);
  static const Color onOrangeContainerLight = Color(0xFFB93800);
  static const Color onOrangeContainerDark = Color(0xFFFFB28A);

  static const Color bgLight = Color(0xFFF6F7F9);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDimLight = Color(0xFFF1F3F6);
  static const Color borderLight = Color(0xFFE5E7EB);
  static const Color textLight = Color(0xFF111827);
  static const Color textMutedLight = Color(0xFF4B5563);

  static const Color bgDark = Color(0xFF0B0F17);
  static const Color surfaceDark = Color(0xFF111827);
  static const Color surfaceMutedDark = Color(0xFF1A2232);
  static const Color surfaceElevatedDark = Color(0xFF1F2937);
  static const Color borderDark = Color(0xFF283548);
  static const Color textDark = Color(0xFFF9FAFB);
  static const Color textMutedDark = Color(0xFF9CA3AF);
}

/// Dedicated Light & Dark themes for LexiLingo Admin:
/// - Signature Orange (`#FF4D00` / `#FF6A1A`) matching Web Admin.
/// - `Be Vietnam Pro` typography with proper Vietnamese diacritic headroom.
/// - Preserves `AppTactileTheme` and `AppStatusColors` extensions.
class AdminTheme {
  const AdminTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseApp = isDark ? AppTheme.darkTheme : AppTheme.lightTheme;

    final primary = isDark
        ? AdminBrandColors.orangeDarkMode
        : AdminBrandColors.orange;
    final primaryContainer = isDark
        ? AdminBrandColors.orangeSoftDark
        : AdminBrandColors.orangeSoftLight;
    final onPrimaryContainer = isDark
        ? AdminBrandColors.onOrangeContainerDark
        : AdminBrandColors.onOrangeContainerLight;
    final bg = isDark ? AdminBrandColors.bgDark : AdminBrandColors.bgLight;
    final surface = isDark
        ? AdminBrandColors.surfaceDark
        : AdminBrandColors.surfaceLight;
    final surfaceContainer = isDark
        ? AdminBrandColors.surfaceMutedDark
        : AdminBrandColors.surfaceDimLight;
    final surfaceContainerHighest = isDark
        ? AdminBrandColors.surfaceElevatedDark
        : AdminBrandColors.borderLight;
    final textPrimary = isDark
        ? AdminBrandColors.textDark
        : AdminBrandColors.textLight;
    final textSecondary = isDark
        ? AdminBrandColors.textMutedDark
        : AdminBrandColors.textMutedLight;
    final outline = isDark
        ? AdminBrandColors.borderDark
        : AdminBrandColors.borderLight;

    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? AdminBrandColors.bgDark : Colors.white,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      surfaceContainer: surfaceContainer,
      surfaceContainerHighest: surfaceContainerHighest,
      outline: outline,
      outlineVariant: outline,
    );

    final baseText = GoogleFonts.beVietnamProTextTheme(baseApp.textTheme).apply(
      bodyColor: textPrimary,
      displayColor: textPrimary,
    );
    final textTheme = baseText.copyWith(
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.32,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.32,
      ),
      titleMedium: baseText.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleSmall: baseText.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      bodyLarge: baseText.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: baseText.bodyMedium?.copyWith(height: 1.42),
      bodySmall: baseText.bodySmall?.copyWith(height: 1.4),
      labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: baseText.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: baseText.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );

    final themed = baseApp.copyWith(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      textTheme: textTheme,
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: outline),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleSpacing: AppSpacing.sm,
        titleTextStyle: GoogleFonts.beVietnamPro(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          height: 1.3,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
    );

    final tactile = AppTactileTheme.from(themed);
    return themed.copyWith(
      extensions: [
        tactile,
        isDark ? AppStatusColors.dark : AppStatusColors.light,
      ],
      filledButtonTheme: FilledButtonThemeData(
        style: tactile.cleanFilledButtonStyle(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: tactile.cleanFilledButtonStyle(),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: tactile.cleanOutlinedButtonStyle(),
      ),
      textButtonTheme: TextButtonThemeData(
        style: tactile.cleanTextButtonStyle(),
      ),
    );
  }
}

/// The admin screens' colour names, resolved from the active theme so they
/// follow light and dark. Read it with `context.ac`.
@immutable
final class AdminPalette {
  const AdminPalette._(this._dark, this._status);

  final bool _dark;
  final AppStatusColors _status;

  Color get primary =>
      _dark ? AdminBrandColors.orangeDarkMode : AdminBrandColors.orange;
  Color get primaryBright => primary;
  Color get onPrimary => _dark ? AdminBrandColors.bgDark : Colors.white;
  Color get primaryContainer => _dark
      ? AdminBrandColors.orangeSoftDark
      : AdminBrandColors.orangeSoftLight;

  Color get background =>
      _dark ? AdminBrandColors.bgDark : AdminBrandColors.bgLight;
  Color get surface =>
      _dark ? AdminBrandColors.surfaceDark : AdminBrandColors.surfaceLight;
  Color get surfaceDim => _dark
      ? AdminBrandColors.surfaceMutedDark
      : AdminBrandColors.surfaceDimLight;
  Color get surfaceContainerLow => _dark
      ? AdminBrandColors.surfaceMutedDark
      : AdminBrandColors.surfaceDimLight;
  Color get surfaceContainerHigh => _dark
      ? AdminBrandColors.surfaceElevatedDark
      : AdminBrandColors.borderLight;

  Color get onSurface =>
      _dark ? AdminBrandColors.textDark : AdminBrandColors.textLight;
  Color get onSurfaceVariant =>
      _dark ? AdminBrandColors.textMutedDark : AdminBrandColors.textMutedLight;
  Color get onSurfaceMuted =>
      _dark ? AdminBrandColors.textMutedDark : AdminBrandColors.textMutedLight;

  Color get success => _status.success;
  Color get successContainer => _status.successContainer;
  Color get warning => _status.warning;
  Color get warningContainer => _status.warningContainer;
  Color get error => _dark
      ? Color.lerp(AppColors.errorBright, AppColors.onGradient, 0.3)!
      : AppColors.error;
  Color get errorContainer =>
      _dark ? AppColors.surfaceDarkMuted : AppColors.errorBg;

  Color get navy => AdminBrandColors.bgDark;
  Color get navyLight => AdminBrandColors.surfaceMutedDark;
  Color get onNavy => AdminBrandColors.textDark;

  Color get outline =>
      _dark ? AdminBrandColors.borderDark : AdminBrandColors.borderLight;
  Color get outlineVariant => outline;
}

extension AdminPaletteContext on BuildContext {
  AdminPalette get ac =>
      AdminPalette._(Theme.of(this).brightness == Brightness.dark, status);
}

extension AdminTextStyle on BuildContext {
  /// Body text from the app theme; screens only choose weight and colour.
  TextStyle adminStyle({FontWeight? fontWeight, Color? color}) => Theme.of(
    this,
  ).textTheme.bodyMedium!.copyWith(fontWeight: fontWeight, color: color);
}
