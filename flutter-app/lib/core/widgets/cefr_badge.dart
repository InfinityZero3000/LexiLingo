import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum CefrBadgeSize { small, medium, large }

/// Consistent CEFR level badge used across vocabulary, course, and game screens.
/// Colors follow the CEFR standard: A=green (beginner), B=blue (intermediate), C=purple (advanced).
class CefrBadge extends StatelessWidget {
  final String level;
  final CefrBadgeSize size;
  final bool outlined;

  const CefrBadge({
    super.key,
    required this.level,
    this.size = CefrBadgeSize.medium,
    this.outlined = false,
  });

  static Color colorForLevel(String level) => switch (level.toUpperCase()) {
    'A1' || 'A2' => AppColors.cefrA,
    'B1' || 'B2' => AppColors.cefrB,
    'C1' || 'C2' => AppColors.cefrC,
    _ => AppColors.grey500,
  };

  static Color _bgForLevel(String level, bool isDark) {
    final base = colorForLevel(level);
    return isDark
        ? base.withValues(alpha: 0.18)
        : base.withValues(alpha: 0.12);
  }

  double get _fontSize => switch (size) {
    CefrBadgeSize.small => 10,
    CefrBadgeSize.medium => 11.5,
    CefrBadgeSize.large => 13,
  };

  EdgeInsetsGeometry get _padding => switch (size) {
    CefrBadgeSize.small =>
      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    CefrBadgeSize.medium =>
      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    CefrBadgeSize.large =>
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  };

  double get _borderRadius => switch (size) {
    CefrBadgeSize.small => 5,
    CefrBadgeSize.medium => 6,
    CefrBadgeSize.large => 7,
  };

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = colorForLevel(level);
    final normalized = level.toUpperCase();

    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : _bgForLevel(level, isDark),
        borderRadius: BorderRadius.circular(_borderRadius),
        border: outlined ? Border.all(color: color, width: 1) : null,
      ),
      child: Text(
        normalized.isEmpty ? '—' : normalized,
        style: TextStyle(
          fontSize: _fontSize,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
          height: 1.2,
        ),
      ),
    );
  }
}
