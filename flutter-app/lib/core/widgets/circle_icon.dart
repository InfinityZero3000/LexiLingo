import 'package:flutter/material.dart';

/// An icon on a tinted disc with a ring in the same hue.
///
/// [solid] fills the disc with [color] instead, for the one icon on a screen
/// that should read as the primary mark.
class CircleIcon extends StatelessWidget {
  const CircleIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 48,
    this.solid = false,
  });

  final IconData icon;
  final Color color;
  final double size;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // A tint of the accent reads on light surfaces only if the glyph is
    // darker than the ring; on dark surfaces the accent itself already is.
    final glyph = solid
        ? theme.colorScheme.onPrimary
        : isDark
        ? color
        : Color.alphaBlend(Colors.black.withValues(alpha: 0.12), color);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: solid ? color : color.withValues(alpha: isDark ? 0.22 : 0.12),
        border: Border.all(
          color: solid ? color : color.withValues(alpha: isDark ? 0.7 : 0.5),
          width: 2,
        ),
      ),
      child: Icon(icon, color: glyph, size: size * 0.5),
    );
  }
}
