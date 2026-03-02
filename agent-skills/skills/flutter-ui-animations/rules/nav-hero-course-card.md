---
name: nav-hero-course-card
description: Use Hero widget on course card thumbnail images to create smooth shared-element transitions to the course detail screen. Tag format — "course-hero-{courseId}".
impact: HIGH
---

# Hero Transition for Course Cards

## Context

The redesigned course list uses horizontal `CourseCard` widgets in category sections. Tapping a card should animate the thumbnail image into the detail screen's header, providing spatial continuity.

## Rule

Wrap the thumbnail `Image` widget in both the card and the detail header with `Hero(tag: 'course-hero-${course.id}')`. Never use a String literal — always interpolate the course ID.

## Correct Implementation

```dart
// features/course/presentation/widgets/horizontal_course_card.dart
import 'package:flutter/material.dart';
import '../../domain/entities/course_entity.dart';
import '../screens/course_detail_screen.dart';

class HorizontalCourseCard extends StatelessWidget {
  final CourseEntity course;

  const HorizontalCourseCard({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CourseDetailScreen(course: course)),
      ),
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: const Color(0xFFE8F4FD),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ← Hero wraps ONLY the image
            Hero(
              tag: 'course-hero-${course.id}',
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Image.network(
                  course.thumbnailUrl,
                  height: 110, width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 110, color: const Color(0xFFBBDEFB),
                    child: const Icon(Icons.school, size: 40, color: Color(0xFF1565C0)),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${course.lessonCount} lessons',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: course.progressFraction,
                    backgroundColor: Colors.grey.shade200,
                    color: const Color(0xFF3B82F6),
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

```dart
// features/course/presentation/screens/course_detail_screen.dart
class CourseDetailScreen extends StatelessWidget {
  final CourseEntity course;
  const CourseDetailScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'course-hero-${course.id}', // ← same tag
                child: Image.network(
                  course.thumbnailUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // ... rest of detail content
        ],
      ),
    );
  }
}
```

## Incorrect Implementation

```dart
// Anti-pattern: hardcoded Hero tag (breaks when multiple cards shown)
Hero(tag: 'course-hero', child: Image.network(url));  // ❌ duplicate tags

// Anti-pattern: Hero wrapping the whole card (causes layout issues)
Hero(
  tag: 'course-hero-${course.id}',
  child: HorizontalCourseCard(course: course),  // ❌ wrap only the image
)

// Anti-pattern: navigating without Hero in destination
// If the destination doesn't have the matching Hero tag, Flutter will show
// a flight error and fall back to a fade transition silently.
```
