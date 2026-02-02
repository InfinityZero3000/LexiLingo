import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';

/// Session Header Widget
/// Clean Code: Single responsibility - display session progress
class SessionHeader extends StatelessWidget {
  final ReviewSessionEntity session;

  const SessionHeader({
    super.key,
    required this.session,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1C2632)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Progress bar
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: session.progress,
                    minHeight: 8,
                    backgroundColor: AppColors.textGrey.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${session.reviewedCards}/${session.totalCards}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatItem(
                icon: Icons.assignment_turned_in,
                label: 'Reviewed',
                value: '${session.reviewedCards}',
                color: AppColors.primary,
              ),
              _StatItem(
                icon: Icons.check_circle,
                label: 'Correct',
                value: '${session.correctCount}',
                color: AppColors.greenSuccess,
              ),
              _StatItem(
                icon: Icons.star,
                label: 'XP',
                value: '+${session.totalXpEarned}',
                color: AppColors.accentYellow,
              ),
              _StatItem(
                icon: Icons.pending,
                label: 'Remaining',
                value: '${session.remainingCards}',
                color: AppColors.textGrey,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textGrey.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
