import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/circle_icon.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_page/continue_learning_card.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

CourseEntity _course(String id, double? progress) => CourseEntity(
  id: id,
  title: 'Course $id',
  level: 'A1',
  language: 'en',
  tags: const [],
  totalXp: 100,
  estimatedDuration: 60,
  totalLessons: 10,
  isPublished: true,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  userProgress: progress,
);

void main() {
  test('picks the first unfinished course, not a completed one', () {
    final picked = ContinueLearningCard.pick([
      _course('done', 100),
      _course('mid', 42),
      _course('new', 0),
    ]);
    expect(picked?.id, 'mid');
  });

  test('falls back to the first course when all are finished', () {
    final picked = ContinueLearningCard.pick([
      _course('a', 100),
      _course('b', 100),
    ]);
    expect(picked?.id, 'a');
  });

  test('nothing to continue when not enrolled anywhere', () {
    expect(ContinueLearningCard.pick(const []), isNull);
  });

  testWidgets('CircleIcon draws the glyph inside a disc', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CircleIcon(icon: PhosphorIconsBold.bell, color: Colors.teal),
        ),
      ),
    );
    expect(find.byIcon(PhosphorIconsBold.bell), findsOneWidget);
    final box = tester.widget<Container>(find.byType(Container).first);
    expect((box.decoration as BoxDecoration).shape, BoxShape.circle);
  });
}
