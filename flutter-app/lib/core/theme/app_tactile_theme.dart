import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TactileSurfaceVariant { elevated, interactive, nested }

@immutable
final class AppTactileTheme extends ThemeExtension<AppTactileTheme> {
  const AppTactileTheme({
    required this.brightness,
    required this.primary,
    required this.onPrimary,
    required this.onSurface,
    required this.pageBackground,
  });

  factory AppTactileTheme.from(ThemeData theme) => AppTactileTheme(
    brightness: theme.brightness,
    primary: theme.colorScheme.primary,
    onPrimary: theme.colorScheme.onPrimary,
    onSurface: theme.colorScheme.onSurface,
    pageBackground: theme.scaffoldBackgroundColor,
  );

  final Brightness brightness;
  final Color primary;
  final Color onPrimary;
  final Color onSurface;
  final Color pageBackground;

  BoxDecoration decoration({
    required TactileSurfaceVariant variant,
    required Color fill,
    Color? accent,
    Color? intermediateFill,
    BorderRadius? borderRadius,
    Set<WidgetState> states = const {},
    String? diagnosticId,
  }) {
    final effectiveFill = intermediateFill ?? fill;
    // ponytail: soft tinted border instead of WCAG-forced high-contrast
    // border — that path picked near-black on light fills, reading as a
    // harsh black frame around every card.
    final borderColor = (accent ?? onSurface).withValues(
      alpha: brightness == Brightness.dark ? 0.28 : 0.14,
    );
    final disabled = states.contains(WidgetState.disabled);
    final pressed = states.contains(WidgetState.pressed);
    final hasShadow = variant != TactileSurfaceVariant.nested && !disabled;
    final shadowColor = brightness == Brightness.dark
        ? Colors.black.withValues(alpha: 0.35)
        : (accent ?? Colors.black).withValues(
            alpha: accent == null ? 0.10 : 0.18,
          );

    return BoxDecoration(
      color: effectiveFill,
      borderRadius: borderRadius ?? BorderRadius.circular(16),
      border: Border.all(
        color: disabled ? onSurface.withValues(alpha: 0.12) : borderColor,
        width: variant == TactileSurfaceVariant.nested ? 1.5 : 2,
      ),
      boxShadow: hasShadow
          ? [
              BoxShadow(
                color: shadowColor,
                blurRadius: 0,
                spreadRadius: 0,
                offset: Offset(0, pressed ? 1 : 4),
              ),
            ]
          : const [],
    );
  }

  ButtonStyle filledButtonStyle({Color? accent}) {
    final base = accent ?? primary;
    final foreground = accent == null ? onPrimary : _blackOrWhite(base);
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? onSurface.withValues(alpha: 0.12)
            : base,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? onSurface.withValues(alpha: 0.38)
            : foreground,
      ),
      side: WidgetStateProperty.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.disabled)
              ? onSurface.withValues(alpha: 0.12)
              : _contrastingBorder(
                  accent: base,
                  fill: base,
                  background: pageBackground,
                ),
          width: 2,
        ),
      ),
      overlayColor: _overlay(onSurface),
      elevation: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return 0;
        return states.contains(WidgetState.pressed) ? 1 : 2;
      }),
    );
  }

  ButtonStyle outlinedButtonStyle({Color? accent}) =>
      _transparentButtonStyle(accent: accent, showSide: (_) => true);

  ButtonStyle textButtonStyle({Color? accent}) => _transparentButtonStyle(
    accent: accent,
    showSide: (states) => states.contains(WidgetState.focused),
  );

  ButtonStyle iconButtonStyle({Color? accent}) =>
      _transparentButtonStyle(accent: accent, showSide: (_) => false);

  ButtonStyle _transparentButtonStyle({
    required Color? accent,
    required bool Function(Set<WidgetState>) showSide,
  }) {
    final base = accent ?? primary;
    return ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? onSurface.withValues(alpha: 0.38)
            : base,
      ),
      side: WidgetStateProperty.resolveWith((states) {
        if (!showSide(states)) return BorderSide.none;
        return BorderSide(
          color: states.contains(WidgetState.disabled)
              ? onSurface.withValues(alpha: 0.12)
              : _contrastingBorder(
                  accent: base,
                  fill: pageBackground,
                  background: pageBackground,
                ),
          width: 2,
        );
      }),
      overlayColor: _overlay(base),
      elevation: const WidgetStatePropertyAll(0),
    );
  }

  WidgetStateProperty<Color?> _overlay(Color color) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return null;
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.focused)) {
          return color.withValues(alpha: 0.12);
        }
        if (states.contains(WidgetState.hovered)) {
          return color.withValues(alpha: 0.08);
        }
        return null;
      });

  Color _contrastingBorder({
    required Color? accent,
    required Color fill,
    required Color background,
    String? diagnosticId,
  }) {
    final candidates = <Color>[];
    if (accent != null) {
      final opaque = Color.fromARGB(
        255,
        (accent.r * 255).round().clamp(0, 255),
        (accent.g * 255).round().clamp(0, 255),
        (accent.b * 255).round().clamp(0, 255),
      );
      final hsl = HSLColor.fromColor(opaque);
      candidates.addAll([
        opaque,
        hsl.withLightness((hsl.lightness - 0.15).clamp(0, 1)).toColor(),
        hsl.withLightness((hsl.lightness + 0.15).clamp(0, 1)).toColor(),
        hsl.withLightness((hsl.lightness - 0.30).clamp(0, 1)).toColor(),
        hsl.withLightness((hsl.lightness + 0.30).clamp(0, 1)).toColor(),
      ]);
    }
    candidates.addAll([onSurface, Colors.black, Colors.white]);

    var winner = candidates.first;
    var winnerScore = -1.0;
    for (final candidate in candidates) {
      final score = math.min(
        contrastRatio(candidate, fill),
        contrastRatio(candidate, background),
      );
      if (score > winnerScore) {
        winner = candidate;
        winnerScore = score;
      }
    }
    if (winnerScore < 3) {
      throw ArgumentError(
        '${diagnosticId ?? 'tactile-surface'}: border '
        '$winner, '
        '${contrastRatio(winner, fill).toStringAsFixed(2)}:1 against fill, '
        '${contrastRatio(winner, background).toStringAsFixed(2)}:1 against page',
      );
    }
    return winner;
  }

  static double contrastRatio(Color a, Color b) {
    final lighter = math.max(a.computeLuminance(), b.computeLuminance());
    final darker = math.min(a.computeLuminance(), b.computeLuminance());
    return (lighter + 0.05) / (darker + 0.05);
  }

  static Color _blackOrWhite(Color background) =>
      contrastRatio(Colors.black, background) >=
          contrastRatio(Colors.white, background)
      ? Colors.black
      : Colors.white;

  @override
  AppTactileTheme copyWith({
    Brightness? brightness,
    Color? primary,
    Color? onPrimary,
    Color? onSurface,
    Color? pageBackground,
  }) => AppTactileTheme(
    brightness: brightness ?? this.brightness,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    onSurface: onSurface ?? this.onSurface,
    pageBackground: pageBackground ?? this.pageBackground,
  );

  @override
  AppTactileTheme lerp(covariant AppTactileTheme? other, double t) {
    if (other == null) return this;
    return AppTactileTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      pageBackground: Color.lerp(pageBackground, other.pageBackground, t)!,
    );
  }
}

class LearnerTheme extends StatelessWidget {
  const LearnerTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final tactile = AppTactileTheme.from(base);
    final neutral = tactile.decoration(
      variant: TactileSurfaceVariant.elevated,
      fill: base.colorScheme.surface,
    );
    final side = (neutral.border! as Border).top;
    final theme = base.copyWith(
      extensions: [...base.extensions.values, tactile],
      cardTheme: CardThemeData(
        color: base.colorScheme.surface,
        elevation: 3,
        shadowColor: Colors.black.withValues(
          alpha: base.brightness == Brightness.dark ? 0.35 : 0.10,
        ),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: side,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: tactile.filledButtonStyle(),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: tactile.filledButtonStyle(),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: tactile.outlinedButtonStyle(),
      ),
      textButtonTheme: TextButtonThemeData(style: tactile.textButtonStyle()),
      iconButtonTheme: IconButtonThemeData(style: tactile.iconButtonStyle()),
    );
    return Theme(data: theme, child: child);
  }
}
