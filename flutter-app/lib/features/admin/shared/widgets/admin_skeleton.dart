import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Animated shimmer skeleton for admin panel loading states.
/// Animates a left-to-right highlight sweep on a muted base color.
class AdminSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const AdminSkeleton({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<AdminSkeleton> createState() => _AdminSkeletonState();
}

class _AdminSkeletonState extends State<AdminSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (_, __) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                (_shimmer.value - 0.3).clamp(0.0, 1.0),
                _shimmer.value.clamp(0.0, 1.0),
                (_shimmer.value + 0.3).clamp(0.0, 1.0),
              ],
              colors: const [
                AppColors.surfaceContainerLow,
                AppColors.surfaceDim,
                AppColors.surfaceContainerLow,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton layout for a KPI stat card (2x2 grid).
class StatCardSkeleton extends StatelessWidget {
  const StatCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AdminSkeleton(width: 36, height: 36, borderRadius: 10),
              const Spacer(),
              const AdminSkeleton(width: 48, height: 22, borderRadius: 6),
            ],
          ),
          const SizedBox(height: 12),
          const AdminSkeleton(width: 80, height: 10, borderRadius: 4),
          const SizedBox(height: 6),
          const AdminSkeleton(width: 60, height: 28, borderRadius: 4),
        ],
      ),
    );
  }
}

/// Skeleton for a full-width section card.
class SectionCardSkeleton extends StatelessWidget {
  final double contentHeight;
  const SectionCardSkeleton({super.key, this.contentHeight = 120});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              AdminSkeleton(width: 120, height: 16, borderRadius: 4),
              AdminSkeleton(width: 60, height: 24, borderRadius: 12),
            ],
          ),
          const SizedBox(height: 8),
          const AdminSkeleton(width: 160, height: 12, borderRadius: 4),
          const SizedBox(height: 16),
          AdminSkeleton(height: contentHeight, borderRadius: 8),
        ],
      ),
    );
  }
}

/// Skeleton for a list row (user / activity row).
class ListRowSkeleton extends StatelessWidget {
  const ListRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const AdminSkeleton(width: 36, height: 36, borderRadius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                AdminSkeleton(width: 120, height: 12, borderRadius: 4),
                SizedBox(height: 6),
                AdminSkeleton(width: 160, height: 10, borderRadius: 4),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const AdminSkeleton(width: 56, height: 22, borderRadius: 11),
        ],
      ),
    );
  }
}
