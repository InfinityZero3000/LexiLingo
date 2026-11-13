import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';

/// Skeleton for the Home layout: header, hero, streak strip, chips, grid.
class HomeSkeletonLoading extends StatelessWidget {
  const HomeSkeletonLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: ShimmerContainer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Row(
              children: [
                SkeletonCircle(size: 48),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonText(width: 160, height: 16),
                      SizedBox(height: 6),
                      SkeletonText(width: 100, height: 12),
                      SizedBox(height: 6),
                      SkeletonText(width: 80, height: 20),
                    ],
                  ),
                ),
                SkeletonCircle(size: 44),
              ],
            ),
            SizedBox(height: 12),
            SkeletonBox(height: 236, borderRadius: 24),
            SizedBox(height: 12),
            SkeletonBox(height: 104, borderRadius: 20),
            SizedBox(height: 12),
            Row(
              children: [
                SkeletonBox(width: 104, height: 44, borderRadius: 22),
                SizedBox(width: 8),
                SkeletonBox(width: 140, height: 44, borderRadius: 22),
              ],
            ),
            SizedBox(height: 16),
            SkeletonText(width: 140, height: 20),
            SizedBox(height: 8),
            SkeletonBox(height: 196, borderRadius: 24),
          ],
        ),
      ),
    );
  }
}
