import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Base shimmer container with consistent styling
class ShimmerContainer extends StatelessWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  
  const ShimmerContainer({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });
  
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: baseColor ?? (isDark ? Colors.grey[700]! : Colors.grey[300]!),
      highlightColor: highlightColor ?? (isDark ? Colors.grey[600]! : Colors.grey[100]!),
      child: child,
    );
  }
}

/// Skeleton box with rounded corners
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 8,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton for text lines
class SkeletonText extends StatelessWidget {
  final double? width;
  final double height;
  
  const SkeletonText({
    super.key,
    this.width,
    this.height = 16,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Skeleton for circular avatars
class SkeletonCircle extends StatelessWidget {
  final double size;
  
  const SkeletonCircle({
    super.key,
    required this.size,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Skeleton card loading for course/lesson items
class SkeletonCard extends StatelessWidget {
  final double? height;
  final EdgeInsets? margin;
  
  const SkeletonCard({
    super.key,
    this.height,
    this.margin,
  });
  
  @override
  Widget build(BuildContext context) {
    return ShimmerContainer(
      child: Container(
        height: height ?? 120,
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SkeletonBox(width: 80, height: 80, borderRadius: 12),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SkeletonText(width: double.infinity, height: 18),
                  const SizedBox(height: 8),
                  SkeletonText(width: MediaQuery.of(context).size.width * 0.4, height: 14),
                  const SizedBox(height: 12),
                  const SkeletonText(width: 100, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton list for multiple items
class SkeletonList extends StatelessWidget {
  final int itemCount;
  final Widget Function(BuildContext, int)? itemBuilder;
  final ScrollPhysics? physics;
  final EdgeInsets? padding;
  
  const SkeletonList({
    super.key,
    this.itemCount = 5,
    this.itemBuilder,
    this.physics,
    this.padding,
  });
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: physics ?? const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      padding: padding,
      itemCount: itemCount,
      itemBuilder: itemBuilder ?? (_, __) => const SkeletonCard(),
    );
  }
}

/// Skeleton for vocabulary card items
class SkeletonVocabCard extends StatelessWidget {
  const SkeletonVocabCard({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ShimmerContainer(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonText(width: 150, height: 20),
                  const SizedBox(height: 8),
                  SkeletonText(width: MediaQuery.of(context).size.width * 0.5, height: 14),
                ],
              ),
            ),
            const SkeletonCircle(size: 40),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for home screen sections
class SkeletonHomeSection extends StatelessWidget {
  const SkeletonHomeSection({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ShimmerContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SkeletonText(width: 150, height: 22),
          ),
          // Horizontal cards
          SizedBox(
            height: 160,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 3,
              itemBuilder: (_, __) => Container(
                width: 200,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton for roadmap/progress items
class SkeletonRoadmapNode extends StatelessWidget {
  const SkeletonRoadmapNode({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ShimmerContainer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          children: [
            const SkeletonCircle(size: 60),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonText(width: 180, height: 18),
                  const SizedBox(height: 8),
                  SkeletonText(width: MediaQuery.of(context).size.width * 0.4, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skeleton for progress stats
class SkeletonProgressStats extends StatelessWidget {
  const SkeletonProgressStats({super.key});
  
  @override
  Widget build(BuildContext context) {
    return ShimmerContainer(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                3,
                (_) => Column(
                  children: const [
                    SkeletonText(width: 60, height: 28),
                    SizedBox(height: 8),
                    SkeletonText(width: 50, height: 14),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const SkeletonBox(width: double.infinity, height: 8, borderRadius: 4),
          ],
        ),
      ),
    );
  }
}
