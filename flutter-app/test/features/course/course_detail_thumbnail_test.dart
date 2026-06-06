import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/course/presentation/screens/course_detail_screen.dart';

void main() {
  group('buildCourseThumbnailCandidates', () {
    test('keeps API, card, and fallback URLs in priority order', () {
      final candidates = buildCourseThumbnailCandidates(
        detailThumbnailUrl: 'https://example.com/detail.jpg',
        initialThumbnailUrl: 'https://example.com/card.jpg',
        fallbackThumbnailUrl: 'https://example.com/fallback.jpg',
      );

      expect(candidates, [
        'https://example.com/detail.jpg',
        'https://example.com/card.jpg',
        'https://example.com/fallback.jpg',
      ]);
    });

    test('uses the card image when the detail API has no image', () {
      final candidates = buildCourseThumbnailCandidates(
        initialThumbnailUrl: 'https://example.com/card.jpg',
      );

      expect(candidates, ['https://example.com/card.jpg']);
    });

    test('ignores blank and duplicate URLs', () {
      final candidates = buildCourseThumbnailCandidates(
        detailThumbnailUrl: ' ',
        initialThumbnailUrl: 'https://example.com/course.jpg',
        fallbackThumbnailUrl: 'https://example.com/course.jpg',
      );

      expect(candidates, ['https://example.com/course.jpg']);
    });
  });
}
