import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';

void main() {
  test('survives the local-cache round trip', () {
    const original = LexiCourseSuggestion(
      courseId: 'c-1',
      title: 'IELTS Prep',
      level: 'B2',
      description: 'Band 5-6',
      thumbnailUrl: 'https://example.test/t.png',
      totalLessons: 24,
      estimatedDuration: 90,
    );

    final restored = LexiCourseSuggestion.fromJson(original.toJson());

    expect(restored.courseId, original.courseId);
    expect(restored.title, original.title);
    expect(restored.level, original.level);
    expect(restored.totalLessons, original.totalLessons);
    expect(restored.estimatedDuration, original.estimatedDuration);
  });

  test('tolerates a server payload with missing optional fields', () {
    final parsed = LexiCourseSuggestion.fromJson({
      'course_id': 'c-2',
      'title': 'Everyday English',
    });

    expect(parsed.level, isNull);
    expect(parsed.totalLessons, 0);
    expect(parsed.estimatedDuration, 0);
  });
}
