import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

// ═══════════════════════════════════════════════════════════════
// Semantic exercise colors
// ═══════════════════════════════════════════════════════════════
const kCorrect = Color(0xFF2DBD73);

const kError = Color(0xFFE53935);

class ExercisePalette {
  final Color primary;
  final Color primaryDeep;
  final Color card;
  final Color surface;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color shadow;

  const ExercisePalette({
    required this.primary,
    required this.primaryDeep,
    required this.card,
    required this.surface,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.shadow,
  });

  factory ExercisePalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ExercisePalette(
      primary: AppColorRoles.primary(isDark),
      primaryDeep: AppColorRoles.primaryDeep(isDark),
      card: theme.colorScheme.surface,
      surface: isDark
          ? theme.colorScheme.surfaceContainerHighest
          : const Color(0xFFE8EFFF),
      border: isDark ? AppColors.borderDarkSoft : const Color(0xFFCDD8F6),
      textPrimary: AppColorRoles.textPrimary(isDark),
      textSecondary: AppColorRoles.textSecondary(isDark),
      textMuted: AppColorRoles.textMuted(isDark),
      shadow: theme.colorScheme.shadow.withValues(alpha: isDark ? 0.2 : 0.05),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Shared helpers
// ═══════════════════════════════════════════════════════════════
