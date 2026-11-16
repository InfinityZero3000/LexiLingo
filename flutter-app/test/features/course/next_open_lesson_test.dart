import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_detail_entity.dart';

LessonInRoadmapEntity _lesson(String id, {bool? locked, bool? done}) =>
    LessonInRoadmapEntity(
      id: id,
      title: id,
      orderIndex: 0,
      lessonType: 'vocabulary',
      xpReward: 10,
      isLocked: locked,
      isCompleted: done,
    );

CourseDetailEntity _course(List<List<LessonInRoadmapEntity>> units) =>
    CourseDetailEntity(
      id: 'c',
      title: 't',
      language: 'en',
      level: 'A1',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      units: [
        for (var i = 0; i < units.length; i++)
          UnitWithLessonsEntity(
            id: 'u$i',
            title: 'u$i',
            orderIndex: i,
            lessons: units[i],
          ),
      ],
    );

void main() {
  test('picks the first open, unfinished lesson across units', () {
    final course = _course([
      [_lesson('a', done: true), _lesson('b', done: true)],
      [_lesson('c'), _lesson('d', locked: true)],
    ]);
    expect(course.nextOpenLesson?.id, 'c');
  });

  test('is null when everything is finished or locked', () {
    expect(
      _course([
        [_lesson('a', done: true)],
      ]).nextOpenLesson,
      isNull,
    );
    expect(
      _course([
        [_lesson('a', locked: true)],
      ]).nextOpenLesson,
      isNull,
    );
  });
}
