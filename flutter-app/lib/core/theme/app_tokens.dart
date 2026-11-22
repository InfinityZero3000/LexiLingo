import 'package:flutter/material.dart';

import 'app_theme.dart';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

abstract final class AppShadows {
  /// Soft card lift; dark surfaces get no shadow and rely on the lifted fill.
  static List<BoxShadow> card(ThemeData theme) =>
      theme.brightness == Brightness.dark
      ? const []
      : [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ];
}

/// Smallest comfortable touch target (>= 44 logical px).
const double kMinTapTarget = 44;

@immutable
final class AppStatusColors extends ThemeExtension<AppStatusColors> {
  const AppStatusColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.infoContainer,
  });

  static const light = AppStatusColors(
    success: AppColors.greenSuccess,
    onSuccess: Colors.white,
    successContainer: AppColors.greenSuccessBg,
    onSuccessContainer: AppColors.greenSuccessDark,
    warning: AppColors.warningDark,
    onWarning: Color(0xFF2B2000),
    warningContainer: AppColors.warningBg,
    onWarningContainer: Color(0xFF5C4400),
    info: AppColors.primary,
    infoContainer: Color(0xFFE1EEFC),
  );

  static const dark = AppStatusColors(
    success: AppColors.successNeon,
    onSuccess: Color(0xFF00210E),
    successContainer: Color(0xFF123524),
    onSuccessContainer: Color(0xFFB7F5D0),
    warning: AppColors.accentYellow,
    onWarning: Color(0xFF3B2F00),
    warningContainer: Color(0xFF3D3414),
    onWarningContainer: Color(0xFFFFE9A8),
    info: AppColors.primaryDarkMode,
    infoContainer: Color(0xFF12353C),
  );

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color info;
  final Color infoContainer;

  @override
  AppStatusColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? infoContainer,
  }) => AppStatusColors(
    success: success ?? this.success,
    onSuccess: onSuccess ?? this.onSuccess,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    info: info ?? this.info,
    infoContainer: infoContainer ?? this.infoContainer,
  );

  @override
  AppStatusColors lerp(ThemeExtension<AppStatusColors>? other, double t) {
    if (other is! AppStatusColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppStatusColors(
      success: l(success, other.success),
      onSuccess: l(onSuccess, other.onSuccess),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      warning: l(warning, other.warning),
      onWarning: l(onWarning, other.onWarning),
      warningContainer: l(warningContainer, other.warningContainer),
      onWarningContainer: l(onWarningContainer, other.onWarningContainer),
      info: l(info, other.info),
      infoContainer: l(infoContainer, other.infoContainer),
    );
  }
}

extension AppThemeContext on BuildContext {
  AppStatusColors get status =>
      Theme.of(this).extension<AppStatusColors>() ??
      (Theme.of(this).brightness == Brightness.dark
          ? AppStatusColors.dark
          : AppStatusColors.light);
}

extension AppTextRoles on TextTheme {
  /// 18px: section headings between titleMedium (16) and titleLarge (22).
  TextStyle? get sectionTitle => titleMedium?.copyWith(fontSize: 18);

  /// 20px: card and dialog headings.
  TextStyle? get heading => titleMedium?.copyWith(fontSize: 20);
}
