import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Theme-following colours for the growth screens, so they read correctly in
/// light and dark instead of the light-only constants.
extension GrowthTone on BuildContext {
  ColorScheme get _scheme => Theme.of(this).colorScheme;

  Color get toneCanvas => Theme.of(this).scaffoldBackgroundColor;
  Color get toneCard => _scheme.surface;
  Color get toneInset => _scheme.surfaceContainerHighest;
  Color get toneText => _scheme.onSurface;
  Color get toneMuted => _scheme.onSurfaceVariant;
  Color get toneLine => _scheme.outlineVariant;
  Color get toneAccent => _scheme.primary;
  Color get toneOnAccent => _scheme.onPrimary;
  Color get toneDanger => _scheme.error;
  Color get toneSuccess => status.success;
  Color get toneWarning => status.warning;
  Color get toneAccentBg => _scheme.primaryContainer;
  Color get toneDangerBg => _scheme.errorContainer;
  Color get toneSuccessBg => status.successContainer;
  Color get toneWarningBg => status.warningContainer;
}
