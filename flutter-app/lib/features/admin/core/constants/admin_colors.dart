import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart' as core;

/// Admin screens' colour names, mapped onto the shared palette in
/// `core/theme/app_theme.dart`. These are light-mode constants for the screens
/// that still read them directly; code that must follow dark mode reads
/// `Theme.of(context).colorScheme` and `context.status` instead.
abstract final class AdminColors {
  static const Color primary = core.AppColors.primary;
  static const Color primaryBright = core.AppColors.primary;
  static const Color primaryContainer = core.AppColors.skyBackground;

  static const Color background = core.AppColors.backgroundLight;
  static const Color surface = core.AppColors.surfaceLight;
  static const Color surfaceDim = core.AppColors.grey100;
  static const Color surfaceContainerLow = core.AppColors.grey50;
  static const Color surfaceContainerHigh = core.AppColors.grey200;

  static const Color onSurface = core.AppColors.textDark;
  static const Color onSurfaceVariant = core.AppColors.textSlate;
  static const Color onSurfaceMuted = core.AppColors.textGrey;

  static const Color success = core.AppColors.greenSuccess;
  static const Color successContainer = core.AppColors.greenSuccessBg;
  static const Color warning = core.AppColors.warningDark;
  static const Color warningContainer = core.AppColors.warningBg;
  static const Color error = core.AppColors.error;
  static const Color errorContainer = core.AppColors.errorBg;

  static const Color navy = core.AppColors.surfaceDarkInk;
  static const Color navyLight = core.AppColors.surfaceDarkCard;

  static const Color outline = core.AppColors.skyBorder;
  static const Color outlineVariant = core.AppColors.grey300;
}
