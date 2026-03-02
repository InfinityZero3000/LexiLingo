---
name: loading-shimmer
description: Replace static CircularProgressIndicator with shimmer skeleton cards shaped like the real content. Use the shimmer package. Match skeleton shape to card dimensions precisely.
impact: HIGH
---

# Shimmer Loading Skeleton Pattern

## Context

Using `CircularProgressIndicator` in the center of a screen causes layout jumps when real content loads. The shimmer pattern pre-renders the content shape, reducing perceived load time.

## Rule

Use the `shimmer` package. Create a `<Feature>ShimmerCard` widget that mirrors the exact layout of the real card (same padding, same height blocks).

## Setup

```yaml
# pubspec.yaml
dependencies:
  shimmer: ^3.0.0
```

## Correct Implementation

```dart
// core/widgets/shimmer_card.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';

class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.shimmerBase,    // e.g. Color(0xFFE0E0E0)
      highlightColor: AppColors.shimmerHighlight, // e.g. Color(0xFFF5F5F5)
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
```

```dart
// features/course/presentation/widgets/course_card_shimmer.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/widgets/shimmer_card.dart';

class CourseCardShimmer extends StatelessWidget {
  const CourseCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: Container(
        width: 180,
        height: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail placeholder
            Container(height: 110, decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(8),
            )),
            const SizedBox(height: 8),
            // Title line
            Container(height: 14, width: 120, color: Colors.white),
            const SizedBox(height: 6),
            // Subtitle line
            Container(height: 12, width: 80, color: Colors.white),
            const SizedBox(height: 8),
            // Progress bar
            Container(height: 6, width: double.infinity,
              decoration: BoxDecoration(color: Colors.white,
                borderRadius: BorderRadius.circular(3))),
          ],
        ),
      ),
    );
  }
}
```

```dart
// Usage in course list screen
return provider.isLoading
  ? SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 4,  // show 4 skeleton cards
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => const CourseCardShimmer(),
      ),
    )
  : RealCourseList(courses: provider.courses);
```

## Shimmer for Profile Stats

```dart
class ProfileStatsShimmer extends StatelessWidget {
  const ProfileStatsShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE0E0E0),
      highlightColor: const Color(0xFFF5F5F5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(4, (_) => Column(
          children: [
            Container(width: 40, height: 24, color: Colors.white),
            const SizedBox(height: 4),
            Container(width: 50, height: 12, color: Colors.white),
          ],
        )),
      ),
    );
  }
}
```

## Incorrect Implementation

```dart
// Anti-pattern: spinner in middle of page
if (isLoading) return const Center(child: CircularProgressIndicator()); // ❌

// Anti-pattern: full-screen shimmer that doesn't match real layout shape
Shimmer.fromColors(
  child: Container(height: 400, color: Colors.white), // ❌ formless blob
);
```
