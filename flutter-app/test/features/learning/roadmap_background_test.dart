import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
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

LessonProgress _lesson(int n) => LessonProgress(
  lessonId: 'l$n',
  lessonNumber: n,
  title: 'Lesson $n',
  isLocked: n > 1,
  isCurrent: n == 1,
  isCompleted: false,
  starsEarned: 0,
  attemptsCount: 0,
  completionPercentage: 0,
  backgroundColor: '#7C4DFF',
);

final _roadmap = CourseRoadmap(
  courseId: 'c',
  courseTitle: 'Course',
  level: 'A1',
  totalUnits: 1,
  completedUnits: 0,
  totalLessons: 6,
  completedLessons: 0,
  completionPercentage: 0,
  totalXpEarned: 0,
  currentStreak: 0,
  units: [
    UnitRoadmap(
      unitId: 'u',
      unitNumber: 1,
      title: 'Unit 1',
      totalLessons: 6,
      completedLessons: 0,
      completionPercentage: 0,
      isCurrent: true,
      lessons: [for (var i = 1; i <= 6; i++) _lesson(i)],
      backgroundColor: '#7C4DFF',
    ),
  ],
);

class _Repo implements LearningRepository {
  @override
  Future<Either<Failure, CourseRoadmap>> getCourseRoadmap(
    String courseId,
  ) async => Right(_roadmap);

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
    // Ahem (the default test font) is a full em wide and reports overflows
    // no device has.
    if (!hasFont) return;
    final loader = FontLoader('Roboto');
    for (final f in ['Regular', 'Bold']) {
      final bytes = File('$fontDir/Roboto-$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });
  setUp(() => EasyLocalization.logger.enableLevels = []);

  final cases = <String, (Size, String)>{
    'phone portrait': (const Size(390, 844), 'background-roadmap.png'),
    'tablet portrait': (const Size(768, 1024), 'background-roadmap.png'),
    'laptop': (const Size(1280, 800), 'background-roadmap-2.png'),
    'wide desktop': (const Size(1920, 1080), 'background-roadmap-2.png'),
    'phone landscape': (const Size(844, 390), 'background-roadmap-2.png'),
  };

  for (final e in cases.entries) {
    testWidgets('roadmap background fills the screen: ${e.key}', (
      tester,
    ) async {
      tester.view.physicalSize = e.value.$1;
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
          providers: [ChangeNotifierProvider.value(value: provider)],
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'Roboto'),
            home: const LearningRoadmapScreen(
              courseId: 'c',
              courseTitle: 'Course',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(Scaffold),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final image = (box.decoration as BoxDecoration).image!;
      expect((image.image as AssetImage).assetName, endsWith(e.value.$2));
      expect(image.fit, BoxFit.cover);
      expect(tester.takeException(), isNull);
    });
  }
}
