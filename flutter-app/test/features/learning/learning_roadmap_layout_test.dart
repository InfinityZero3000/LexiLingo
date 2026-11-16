import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/learning/domain/entities/course_roadmap.dart';
import 'package:lexilingo_app/features/learning/domain/repositories/learning_repository.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/complete_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_course_roadmap_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/get_lesson_content_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/start_lesson_usecase.dart';
import 'package:lexilingo_app/features/learning/domain/usecases/submit_answer_usecase.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_roadmap_screen.dart';
import 'package:provider/provider.dart';

LessonProgress _lesson(int i, {bool current = false}) => LessonProgress(
  lessonId: 'l$i',
  lessonNumber: i,
  title: "Verb 'To Be' with a rather long lesson title $i",
  isLocked: i > 1,
  isCurrent: current,
  isCompleted: false,
  starsEarned: 0,
  attemptsCount: 0,
  completionPercentage: 0,
  backgroundColor: '#58CC02',
);

CourseRoadmap _roadmap() => CourseRoadmap(
  courseId: 'course',
  courseTitle: 'Course',
  level: 'A1',
  totalUnits: 1,
  completedUnits: 0,
  totalLessons: 9,
  completedLessons: 0,
  completionPercentage: 0,
  totalXpEarned: 0,
  currentStreak: 0,
  units: [
    UnitRoadmap(
      unitId: 'u1',
      unitNumber: 1,
      title: 'Unit 1',
      totalLessons: 9,
      completedLessons: 0,
      completionPercentage: 0,
      isCurrent: true,
      lessons: [for (var i = 1; i <= 9; i++) _lesson(i, current: i == 1)],
      backgroundColor: '#58CC02',
    ),
  ],
);

class _Repo implements LearningRepository {
  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(String id) async =>
      Right(_roadmap());

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused');
}

void main() {
  final fontDir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '/usr/local/share/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final hasFont = File('$fontDir/Roboto-Regular.ttf').existsSync();

  setUpAll(() async {
    if (!hasFont) return;
    final loader = FontLoader('Roboto');
    for (final f in ['Regular', 'Bold']) {
      final bytes = File('$fontDir/Roboto-$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });
  setUp(() => EasyLocalization.logger.enableLevels = []);

  for (final w in [320, 375, 768, 1280, 1600]) {
    testWidgets('roadmap stays inside its column at ${w}px', skip: !hasFont, (
      tester,
    ) async {
      tester.view.physicalSize = Size(w.toDouble(), 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final repo = _Repo();
      final provider = LearningProvider(
        startLessonUseCase: StartLessonUseCase(repository: repo),
        submitAnswerUseCase: SubmitAnswerUseCase(repository: repo),
        completeLessonUseCase: CompleteLessonUseCase(repository: repo),
        getCourseRoadmapUseCase: GetCourseRoadmapUseCase(repository: repo),
        getLessonContentUseCase: GetLessonContentUseCase(repository: repo),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider<CourseProvider>(
              create: (_) => throw UnimplementedError(),
              lazy: true,
            ),
          ],
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: const LearningRoadmapScreen(
              courseId: 'course',
              courseTitle: 'C',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);

      final column = tester.getRect(find.byKey(const Key('roadmapColumn')));
      expect(column.width, lessThanOrEqualTo(kRoadmapColumnMaxWidth));
      expect(
        column.width,
        w < kRoadmapColumnMaxWidth ? w : kRoadmapColumnMaxWidth,
      );
      expect(column.center.dx, closeTo(w / 2, 0.5));

      final zigzag = tester.getRect(find.byKey(const Key('roadmapZigzag')));
      for (var i = 1; i <= 9; i++) {
        final finder = find.byKey(ValueKey('roadmapNode-$i'));
        final r = tester.getRect(finder);
        expect(
          r.left,
          greaterThanOrEqualTo(column.left + 8),
          reason: 'node $i',
        );
        expect(r.right, lessThanOrEqualTo(column.right - 8), reason: 'node $i');
        expect(r.top, greaterThanOrEqualTo(zigzag.top), reason: 'node $i');
      }

      final label = tester.getRect(
        find.byKey(const Key('roadmapCurrentLabel')),
      );
      expect(label.top, greaterThanOrEqualTo(zigzag.top));
      expect(label.left, greaterThanOrEqualTo(column.left));
      expect(label.right, lessThanOrEqualTo(column.right));
    });
  }
}
