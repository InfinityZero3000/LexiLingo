import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';
import 'package:lexilingo_app/features/progress/presentation/screens/my_progress_screen.dart';
import 'package:lexilingo_app/features/social/social.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Quick Actions Grid - Navigate to new gamification/social features
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _QuickActionButton(
            icon: Icons.store,
            label: 'profile.shop'.tr(),
            color: AppColors.orange,
            gradient: AppColors.warmGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ShopScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.leaderboard,
            label: 'profile.ranks'.tr(),
            color: AppColors.greenSuccess,
            gradient: AppColors.successGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LeaderboardScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.people,
            label: 'profile.friends'.tr(),
            color: AppColorRoles.primary(
              Theme.of(context).brightness == Brightness.dark,
            ),
            gradient: Theme.of(context).brightness == Brightness.dark
                ? AppColors.primaryGradientDark
                : AppColors.indigoGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SocialScreen()),
            ),
          ),
          const SizedBox(width: 12),
          _QuickActionButton(
            icon: Icons.insights_rounded,
            label: 'profile.progress'.tr(),
            color: AppColors.purple,
            gradient: AppColors.purpleGradient,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyProgressScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.surface,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.surface,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
