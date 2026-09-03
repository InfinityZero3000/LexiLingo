import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_thumbnail_resolver.dart';

void main() {
  group('courseFallbackThumbnailUrl', () {
    test('uses a matching tag before the course level', () {
      final course = _course(tags: const ['grammar'], level: 'advanced');

      expect(
        courseFallbackThumbnailUrl(course),
        anyOf(
          contains('photo-1471899236350'),
          contains('photo-1432821596592'),
          contains('photo-1455390582262'),
        ),
      );
    });

    test('uses the level catalog when no tag matches', () {
      final course = _course(level: 'beginner');

      expect(
        courseFallbackThumbnailUrl(course),
        anyOf(
          contains('photo-1427504494785'),
          contains('photo-1506880018603'),
          contains('photo-1512820790803'),
        ),
      );
    });

    test('returns the same image for the same course ID', () {
      final first = _course(id: 'stable-course-id', tags: const ['travel']);
      final second = _course(id: 'stable-course-id', tags: const ['travel']);

      expect(
        courseFallbackThumbnailUrl(first),
        courseFallbackThumbnailUrl(second),
      );
    });

    test('does not select the removed Unsplash image', () {
      final urls = List.generate(
        30,
        (index) => courseFallbackThumbnailUrl(
          _course(id: 'ielts-$index', tags: const ['ielts']),
        ),
      );

      expect(urls, everyElement(isNot(contains('photo-1523050854058'))));
    });
  });

  group('buildCourseCardThumbnailCandidates', () {
    test('puts a non-empty backend thumbnail before the fallback', () {
      final candidates = buildCourseCardThumbnailCandidates(
        _course(thumbnailUrl: ' https://example.com/course.jpg '),
      );

      expect(candidates.first, 'https://example.com/course.jpg');
      expect(candidates, hasLength(2));
    });

    test('ignores a blank backend thumbnail', () {
      final course = _course(thumbnailUrl: ' ');

      expect(buildCourseCardThumbnailCandidates(course), [
        courseFallbackThumbnailUrl(course),
      ]);
    });
  });
}

CourseEntity _course({
  String id = 'course-1',
  List<String> tags = const [],
  String level = 'intermediate',
  String? thumbnailUrl,
}) {
  final now = DateTime(2026, 6, 7);
  return CourseEntity(
    id: id,
    title: 'Test Course',
    language: 'en',
    level: level,
    tags: tags,
    thumbnailUrl: thumbnailUrl,
    totalXp: 100,
    estimatedDuration: 60,
    totalLessons: 3,
    isPublished: true,
    createdAt: now,
    updatedAt: now,
  );
}
