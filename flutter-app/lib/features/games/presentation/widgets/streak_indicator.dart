import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Fire streak indicator showing consecutive days of activity.
///
/// When streak >= 3, adds a warm glow effect.
class StreakIndicator extends StatelessWidget {
  final int streakDays;
  final bool compact;

  const StreakIndicator({
    super.key,
    required this.streakDays,
    this.compact = false,
  });

  bool get _hasGlow => streakDays >= 3;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact();
    }
    return _buildFull();
  }

  Widget _buildCompact() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: _hasGlow
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
              color: AppColors.orange.withValues(alpha: 0.1),
            )
          : BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.orange.withValues(alpha: 0.1),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Colors.orange,
            size: 16,
          ),
          const SizedBox(width: 3),
          Text(
            '$streakDays',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: streakDays > 0
                  ? Colors.orange.shade800
                  : AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFull() {
    final color = streakDays > 0 ? Colors.orange.shade800 : AppColors.textGrey;
    final bgColor = streakDays > 0
        ? AppColors.orange.withValues(alpha: 0.1)
        : AppColors.grey200;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: _hasGlow
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            color: Colors.orange,
            size: _hasGlow ? 22 : 18,
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$streakDays day${streakDays != 1 ? 's' : ''}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: color,
                ),
              ),
              Text(
                'streak',
                style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
