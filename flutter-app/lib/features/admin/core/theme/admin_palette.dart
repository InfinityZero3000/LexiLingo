import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// The admin screens' colour names, resolved from the active theme so they
/// follow light and dark. Read it with `context.ac`.
@immutable
final class AdminPalette {
  const AdminPalette._(this._dark, this._status);

  final bool _dark;
  final AppStatusColors _status;

  Color get primary => _dark ? AppColors.primaryDarkMode : AppColors.primary;
  Color get primaryBright => primary;
  Color get onPrimary =>
      _dark ? AppColors.backgroundDark : AppColors.onGradient;
  Color get primaryContainer =>
      _dark ? AppColors.surfaceDarkCard : AppColors.skyBackground;

  Color get background =>
      _dark ? AppColors.backgroundDark : AppColors.backgroundLight;
  Color get surface => _dark ? AppColors.surfaceDark : AppColors.surfaceLight;
  Color get surfaceDim =>
      _dark ? AppColors.surfaceDarkMuted : AppColors.grey100;
  Color get surfaceContainerLow =>
      _dark ? AppColors.surfaceDarkMuted : AppColors.grey50;
  Color get surfaceContainerHigh =>
      _dark ? AppColors.surfaceDarkElevated : AppColors.grey200;

  Color get onSurface =>
      _dark ? AppColors.textOnDarkPrimary : AppColors.textDark;
  Color get onSurfaceVariant =>
      _dark ? AppColors.textOnDarkSecondary : AppColors.textSlate;
  Color get onSurfaceMuted =>
      _dark ? AppColors.textOnDarkSecondary : AppColors.grey700;

  Color get success => _status.success;
  Color get successContainer => _status.successContainer;
  Color get warning => _status.warning;
  Color get warningContainer => _status.warningContainer;
  Color get error => _dark
      ? Color.lerp(AppColors.errorBright, AppColors.onGradient, 0.3)!
      : AppColors.error;
  Color get errorContainer =>
      _dark ? AppColors.surfaceDarkMuted : AppColors.errorBg;

  Color get navy => AppColors.surfaceDarkInk;
  Color get navyLight => AppColors.surfaceDarkCard;
  Color get onNavy => AppColors.textOnDarkPrimary;

  Color get outline => _dark ? AppColors.borderDarkSoft : AppColors.skyBorder;
  Color get outlineVariant =>
      _dark ? AppColors.borderDarkSoft : AppColors.grey300;
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
